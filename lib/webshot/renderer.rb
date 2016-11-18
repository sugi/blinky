require 'webshot/errors'
require 'webshot/utils'
require 'webshot/request'
require 'webshot/magick_effector'
require 'capybara/poltergeist'
require 'tmpdir'
require 'uri'
require 'pp'
require 'timeout'

module WebShot
  class Renderer
    include Utils

    def initialize
      @driver_no = 0
      @driver_req_count = 0
      @webkit_server = nil
      logger.debug 'Initialized'
    end
    attr_reader :driver
    attr_reader :driver_no
    attr_reader :driver_req_count

    def driver
      @driver and return @driver
      @driver_req_count = 0
      @driver_no += 1
      dopts = {
        timeout: config.webkit_comminucation_timeout,
        phantomjs_options: %w(--ignore-ssl-errors=true --local-url-access=false),
        #phantomjs_logger: config.logger_out,
        phantomjs_logger: "",
      }
      if config.proxy
        dopts[:phantomjs_options] << "--proxy=#{config.proxy}"
      end
      if logger.level == Logger::DEBUG
        wrap_logger = Object.new
        wrap_logger.instance_variable_set("@logger", new_logger(progname: "Poltergeist"))
        def wrap_logger.puts(v)
          @logger.debug v
        end
        dopts[:logger] = wrap_logger
      end
      @driver = Capybara::Poltergeist::Driver.new "webshot-#{@driver_no}", dopts
    end

    def renew_driver
      logger.info "Trying to renew driver..."
      @driver.quit
      @driver = nil
    end

    def save_url_to_file(uri, file, width, height)
      begin
        start_time = Time.now
        driver.resize(width, height)
        driver.visit uri.to_s
        Timeout::timeout(config.webkit_load_timeout) do
          sleep_time = 1
          loop do |n|
            sleep sleep_time
            if driver.evaluate_script('document.readyState') == "complete"
              logger.debug("Page load complete (#{Time.now.to_f - start_time.to_f} secs). Saving screenshot...")
              break
            end
            sleep_time += 0.5
          end
        end
      rescue Timeout::Error => e
        logger.info("Page load was not complete within #{config.webkit_load_timeout} secs. Saving screenshot forcely...")
      end
      driver.execute_script %q{
        if (!document.body.bgColor) { document.body.bgColor = 'white'; }
        document.body.style.overflow = 'hidden';
      }
      @driver_req_count += 1
      driver.save_screenshot file, full: false
    end

    def render(req)
      driver_req_count > config.webkit_max_request and reset_driver
      logger.info "Start rendering, URI: #{req.uri}"
      logger.debug "Render request detail: #{req.to_hash.dup.tap{|r| r.delete(:uri)}.inspect}"
      tmppath = File.join Dir.tmpdir, Dir::Tmpname.make_tmpname('ss-', '.png')
      tries = 0
      begin
        tries += 1
        save_url_to_file req.uri, tmppath, req.winsize_x, req.winsize_y
      rescue Capybara::Poltergeist::DeadClient, Capybara::Poltergeist::TimeoutError => e
        if tries < config.webkit_crash_retry
          logger.error "The phantomjs process died! trying reset driver..."
          renew_driver
          retry
        else
          logger.error "Server crashed 3 times, give up!"
          raise e
        end
      end
      driver.reset!
      img = Magick::Image.read(tmppath)[0]
      File.unlink(tmppath)
      img.background_color = 'white'
      img = MagickEffector.all img, req
      logger.debug "Rendering is completed (#{req.uri})"
      ret = img.to_blob
      img.destroy!
      ret
    end

  end
end
