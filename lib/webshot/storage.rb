require 'pstore'
require 'webshot/utils'
require 'webshot/request'
require 'webshot/magick_effector'
require 'bunny'
require 'fileutils'
require 'thread'

module WebShot
  class Storage
    include Utils
    @@instances = {}

    def self.get_instance(basepath = nil)
      basepath ||= config.storage_dir
      @@instances[basepath] and return @@instances[basepath]
      @@instances[basepath] = new(basepath)
    end

    def initialize(basepath = nil)
      @basepath = basepath || config.storage_dir
      @queue_refresh_time = 600
      @image_refresh_time = 3 * 24 * 3600
      @mq_server = config.mq_server
      @mq_conn = nil
      @mq_req = nil
      @mq_ret = nil
      FileUtils.mkdir_p @basepath
      logger.debug "Initalized (dir: #{@basepath})"
      @mutexes = Hash.new {|h, k| h[k] = Mutex.new }
      @mutexes[:conn]; @mutexes[:ret]; @mutexes[:ret]; # pre-create...
    end
    attr_reader :basepath
    attr_accessor :queue_refresh_time, :image_refresh_time, :mq_server
    attr_writer :mq_conn, :mq_req, :mq_ret

    def mq_conn
      @mutexes[:conn].synchronize do
        @mq_conn and return @mq_conn
        conn = @mq_conn = Bunny.new(mq_server)
        @mq_conn.start
        at_exit {
          conn && conn.close
        }
        @mq_conn
      end
    end

    def mq_req
      @mutexes[:req].synchronize do
        @mq_req and return @mq_req
        ch = mq_conn.create_channel
        @mq_req = ch.queue("shot-requests")
      end
    end

    def mq_ret
      @mutexes[:ret].synchronize do
        @mq_ret and return @mq_ret
        ch = mq_conn.create_channel
        @mq_ret = ch.queue("shot-results", durable: true)
      end
    end

    def fetch(req, force_queue = false)
      force_queue ? enqueue(req) : auto_enqueue(req)

      path = File.join(basepath, req.ident[0, 2], req.ident[0, 4], req.ident) + ".png"
      info = {}
      pinfo(req).transaction(true) do |ps|
        info = ps.to_hash
      end
      unless File.exists? path
        return info.merge(mtime: info[:queued_at], uri: req.uri,
                          etag: req.ident + '@' + info[:queued_at].to_f.to_s,
                          blob: MagickEffector.gen_waitimage(req).to_blob)
      end

      info.merge(mtime: info[:updated_at], uri: req.uri,
                 etag: req.ident + '@' + info[:updated_at].to_f.to_s,
                 blob: File.read(path))
    end

    def auto_enqueue(req)
      path = get_path(req)

      last_queued_at = nil
      failed = false
      pinfo(req).transaction(true) do |ps|
        last_queued_at = ps[:queued_at]
        failed = ps[:failed]
      end

      if File.exists?(path) && !failed &&
          File.mtime(path).to_i + image_refresh_time > Time.now.to_i
        return false
      end

      if last_queued_at && last_queued_at.to_i + queue_refresh_time > Time.now.to_i
         return false
      end

      enqueue(req)
    end

    def enqueue(req)
      mq_req.publish(Marshal.dump(req), persistent: true)
      pinfo(req).transaction do |ps|
        ps[:queued_at] = Time.now
      end
      logger.info "Add reqeust queue: #{req.to_hash.inspect}"
    end

    def dequeue(block_p = true)
      mq_req.subscribe(block: block_p) do |del_info, props, body|
        Thread.current.abort_on_exception = true
        ret = Marshal.load(body)
        #logger.debug "Dequeue: #{ret.inspect}"
        yield ret
      end
    end

    def push_result(req, blob)
      ret = {req: req}
      logger.info "Add result to queue: blob length = #{blob.length}, #{req.to_hash.inspect} "
      ret[:blob] = blob
      mq_ret.publish(Marshal.dump(ret), persistent: true)
    end

    def pinfo(req)
      path = get_path(req)
      FileUtils.mkdir_p File.dirname(path)
      pinfo = PStore.new("#{path}.info")
      def pinfo.to_hash
        Hash[self.roots.map {|k| [k, self[k]] }]
      end
      pinfo
    end

    def flush(block_p = true)
      begin
        mq_ret.subscribe(block: block_p) do |del_info, props, body|
          ret = Marshal.load(body)
          req = ret[:req]
          path = get_path(req)
          info = req.to_hash.merge updated_at: Time.now
          if !ret[:blob] || ret[:blob].empty? || ret[:blob] == 'false'
            File.write(path, MagickEffector.gen_failimage(req).to_blob)
            info[:failed] = true
            info[:last_failed_at] = Time.now
          else
            File.write(path, ret[:blob])
            info[:failed] = false
          end
          pinfo(req).transaction do |ps|
            info.each do |k, v|
              ps[k.to_sym] = v
            end
          end
          logger.info "Flush image:#{info[:failed] ? ' [FAILED]' : ''} #{path} (#{req.uri})"
        end
      rescue Interrupt => e
        # exit
      end
    end

    def get_path(req)
      File.join(basepath, req.ident[0, 2], req.ident[0, 4], req.ident) + ".png"
    end

  end
end
