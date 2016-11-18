require 'pstore'
require 'webshot/version'
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

    def initialize(basepath = nil, opts = {})
      @basepath = basepath || config.storage_dir
      @queue_refresh_time = config.queue_refresh_time
      @image_refresh_time = config.image_refresh_time
      @amq_uri = config.amq_uri
      @mq_conn = nil
      @mq_req = nil
      @mq_ret = nil
      @mq_threaded = true
      FileUtils.mkdir_p @basepath
      logger.debug "Initalized (dir: #{@basepath})"
      @mutexes = Hash.new {|h, k| h[k] = Mutex.new }
      @mutexes[:conn]; @mutexes[:ret]; @mutexes[:ret]; # pre-create...
      opts.each {|k, v| public_send "#{k}=", v }
    end
    attr_reader :basepath, :mq_ch_req, :mq_ch_ret
    attr_accessor :queue_refresh_time, :image_refresh_time, :amq_uri, :mq_threaded

    def mq_conn
      @mutexes[:conn].synchronize do
        @mq_conn and return @mq_conn
        conn = @mq_conn = Bunny.new(amq_uri, threaded: mq_threaded, logger: Utils.new_logger(progname: 'Bunny'))
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
        @mq_ch_req = mq_conn.create_channel
        @mq_ch_req.prefetch(10)
        @mq_req = @mq_ch_req.queue("shot-requests", arguments: {'x-max-priority' => 10})
      end
    end

    def mq_ret
      @mutexes[:ret].synchronize do
        @mq_ret and return @mq_ret
        @mq_ch_ret = mq_conn.create_channel
        @mq_ch_ret.prefetch(1024)
        @mq_ret = @mq_ch_ret.queue("shot-results", durable: true)
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
                          cache_control: :no_cache, status: 'waiting',
                          etag: req.ident + '@' + info[:queued_at].to_f.to_s,
                          blob: MagickEffector.gen_waitimage_blob(req))
      end

      info.merge(mtime: info[:updated_at], uri: req.uri, status: 'stable',
                 etag: req.ident + '@' + info[:updated_at].to_f.to_s,
                 cache_control: :public, blob: File.read(path, encoding: 'ascii-8bit'))
    end

    def auto_enqueue(req)
      path = get_path(req)

      last_queued_at = nil
      failed = false
      qargs = {priority: 0}
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

      failed         and qargs[:priority] += 1
      last_queued_at  or qargs[:priority] += 2

      enqueue(req, qargs)
    end

    def enqueue(req, qargs = {})
      mq_req.publish(Marshal.dump(req), {persistent: true}.merge(qargs))
      pinfo(req).transaction do |ps|
        ps[:updated_at] = ps[:queued_at] = Time.now
      end
      logger.info "Add reqeust queue: #{req.to_hash.inspect}"
    end

    def dequeue(block_p = true)
      mq_req.subscribe(block: block_p, manual_ack: true) do |del_info, props, body|
        #Thread.current.abort_on_exception = true
        req = Marshal.load(body)
        #logger.debug "Dequeue: #{req.inspect}"
        yield req
        mq_ch_req.ack(del_info.delivery_tag.to_i)
      end
    end

    def push_result(req, blob_or_msg, is_error = false)
      ret = {req: req}
      if is_error
        ret[:message] = blob_or_msg
        ret[:error] = true
        logger.info "Add result to queue: failed (#{blob_or_msg}) #{req.to_hash.inspect}"
      else
        logger.info "Add result to queue: blob length = #{blob_or_msg.to_s.length} (#{req.uri})"
        ret[:blob] = blob_or_msg
      end
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
      mq_ret.subscribe(block: block_p, manual_ack: true) do |del_info, props, body|
        ret = Marshal.load(body)
        req = ret[:req]
        path = get_path(req)
        info = req.to_hash.merge updated_at: Time.now
        if ret[:error] || !ret[:blob] || ret[:blob].empty?
          pinfo(req).transaction(true) do |pi|
            info[:failcount] = pi[:failcount].to_i + 1
          end
          info[:error_message] = ret[:message]
          info[:failed] = true
          info[:last_failed_at] = Time.now
          logger.debug "Update fail count for #{req.uri}"
          if info[:failcount] >= config.failimage_maxtry
            logger.debug "Max fail count has been exceeded (#{info[:failcount]} >= #{config.failimage_maxtry})"
            File.write(path, MagickEffector.gen_failimage_blob(req))
            logger.info "Flush FAILED image: #{path} (#{req.uri})"
          end
        else
          info[:failed] = false
          File.write(path, ret[:blob])
          logger.info "Flush image: #{path} (#{req.uri})"
        end
        pinfo(req).transaction do |ps|
          info.each do |k, v|
            ps[k.to_sym] = v
          end
        end
        logger.debug "Flush image info: #{path}.info"
        mq_ch_ret.ack(del_info.delivery_tag.to_i)
      end
    end

    def get_path(req)
      File.join(basepath, req.ident[0, 2], req.ident[0, 4], req.ident) + ".png"
    end

  end
end
