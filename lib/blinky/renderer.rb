require 'blinky/errors'
require 'blinky/utils'
require 'blinky/request'
require 'blinky/magick_effector'
require 'capybara/poltergeist'
require 'tmpdir'
require 'uri'
require 'pp'
require 'timeout'

module Blinky
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
        timeout: config.webkit_load_timeout,
        js_errors: false,
        phantomjs_options: %w(--ignore-ssl-errors=true --local-url-access=false --ssl-protocol=ANY),
        #phantomjs_logger: config.logger_out,
        phantomjs_logger: File.open('/dev/null', 'w')
      }
      if config.proxy_uri
        dopts[:phantomjs_options] << "--proxy=#{config.proxy_uri}"
      end
      if logger.level == Logger::DEBUG
        wrap_logger = Object.new
        wrap_logger.instance_variable_set("@logger", new_logger(progname: "Poltergeist"))
        def wrap_logger.puts(v)
          @logger.debug v
        end
        dopts[:logger] = wrap_logger
      end
      @driver = Capybara::Poltergeist::Driver.new "blinky-#{@driver_no}", dopts
    end

    def renew_driver
      logger.info "Trying to renew driver..."
      begin
        @driver && @driver.quit
      rescue => e
        logger.error "Get error on driver shutdown #{e.inspect}: #{e.mssage}"
      end
      @driver = nil
    end

    def save_url_to_file(uri, file, width, height)
      start_time = Time.now
      load_tries = 0
      begin
        load_tries += 1
        driver.visit uri.to_s
      rescue Capybara::Poltergeist::StatusFailError => e
        logger.error "Failed to load page (#{uri}): #{e.message}"
        if load_tries <= Blinky.config.webkit_load_retry
          logger.error "Retry to page load (#{load_tries}/#{Blinky.config.webkit_load_retry})..."
          renew_driver
          retry
        else
          logger.error "Retry limit has been exceeded, going to continue..."
        end
      end
      driver.resize width, height
      begin
        Timeout::timeout(config.page_complete_timeout) do
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
        logger.info("Page load was not complete within #{config.page_complete_timeout} secs. Saving screenshot forcely...")
      end
      unless driver.status_code
        renew_driver # for safe
        raise URILoadFailed.new("Status code is nil. It might fail to contant server.")
      end
      driver.execute_script %q{
        if (!document.body.bgColor) { document.body.bgColor = 'white'; }
        document.body.style.overflow = 'hidden';
      }
      @driver_req_count += 1
      driver.save_screenshot file, full: false
    end

    def render(req)
      driver_req_count > config.webkit_max_request and renew_driver
      logger.info "Start rendering, URI: #{req.uri}"
      logger.debug "Render request detail: #{req.to_hash.dup.tap{|r| r.delete(:uri)}.inspect}"
      tmppath = File.join Dir.tmpdir, "ss-#{Time.now.strftime("%Y%m%d")}-#{rand(0x100000000).to_s(36)}.png"
      tries = 0
      begin
        tries += 1
        save_url_to_file req.uri, tmppath, req.winsize_x, req.winsize_y
      rescue Capybara::Poltergeist::DeadClient, Capybara::Poltergeist::TimeoutError => e
        if tries < config.webkit_crash_retry
          logger.error "The phantomjs process error (#{e.inspect})! Trying reset driver..."
          renew_driver
          retry
        else
          logger.error "Server crashed 3 times, give up!"
          raise e
        end
      end
      begin
        driver.reset!
      rescue Capybara::Poltergeist::BrowserError, Capybara::Poltergeist::DeadClient => e
        logger.error "Get error on resetting driver #{e.inspect}: #{e.message}"
        renew_driver
      end
      img = Magick::Image.read(tmppath)[0]
      File.unlink(tmppath)
      img.background_color = 'white'
      img = MagickEffector.all img, req
      logger.debug "Rendering is completed (#{req.uri})"
      blob = img.to_blob
      img.destroy!
      blob
    end

  end
end
