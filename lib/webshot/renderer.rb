require 'webshot/errors'
require 'webshot/utils'
require 'webshot/request'
require 'webshot/magick_effector'
require 'capybara-webkit'
require 'tmpdir'
require 'uri'
require 'pp'

module WebShot
  class Renderer
    include Utils

    def initialize
      Capybara::Webkit.configure do |config|
        config.frozen? and next
        config.allow_unknown_urls
        config.ignore_ssl_errors
        config.timeout = WebShot.config.webkit_load_timeout
        if WebShot.config.proxy
          uri = URI.parse(WebShot.config.proxy)
          proxy_info = {host: uri.host, port: uri.port}
          uri.user     and proxy_info[:user] = uri.user
          uri.password and proxy_info[:pass] = uri.password
          config.use_proxy proxy_info
        end
        logger.debug "Webkit Config: #{config.inspect}"
      end

      logger.debug 'Initialized'
      @driver_no = 0
      @driver_req_count = 0
      @webkit_server = nil
    end
    attr_reader :driver
    attr_reader :driver_no
    attr_reader :driver_req_count

    def driver
      @driver and return @driver
      dopts = Capybara::Webkit::Configuration.to_hash
      @driver_req_count = 0
      @driver_no += 1
      @webkit_server = Capybara::Webkit::Server.new(dopts)
      @driver = Capybara::Webkit::Driver.new "webshot-#{@driver_no}", dopts.dup.merge(server: @webkit_server)
    end

    def renew_driver
      logger.info "Trying to renew driver..."
      old_wserv = @webkit_server
      @webkit_server = nil
      @driver = nil
      begin
        old_wserv.pid && Process.kill("TERM", old_wserv.pid)
      rescue => e
        logger.error "Error on stop server #{e.inspect}"
      end
      driver
      sleep config.webkit_renew_sleep
    end

    def save_url_to_file(uri, file, width, height)
      driver.visit uri.to_s
      i = 1
      while i < 8
        break if driver.evaluate_script('document.readyState') == "complete"
        sleep 0.1 * i
        i += 1
      end
      driver.execute_script "document.body.style.overflow = 'hidden';"
      @driver_req_count += 1
      driver.save_screenshot file, width: width, height: height, resize_to_contents: false, show_pointer: false
    end

    def render(req)
      logger.info "Start rendering, URI: #{req.uri}"
      logger.debug "Render request detail: #{req.to_hash.dup.tap{|r| r.delete(:uri)}.inspect}"
      tmppath = File.join Dir.tmpdir, Dir::Tmpname.make_tmpname('ws-', '.png')
      tries = 0
      begin
        tries += 1
        save_url_to_file req.uri, tmppath, req.winsize_x, req.winsize_y
      rescue Capybara::Webkit::CrashError => e
        if tries < config.webkit_crash_retry
          logger.error "The webkit_server process crashed! trying reset driver..."
          @driver = nil
          retry
        else
          logger.error "Server crashed 3 times, give up!"
          raise e
        end
      end
      driver.visit 'about:blank'
      img = Magick::Image.read(tmppath)[0]
      File.unlink(tmppath)
      img = MagickEffector.all img, req
      driver_req_count > config.webkit_max_request and renew_driver
      logger.debug "Rendering is completed (#{req.uri})"
      img.to_blob
    end

  end
end
