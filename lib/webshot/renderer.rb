require 'webshot/errors'
require 'webshot/utils'
require 'webshot/request'
require 'webshot/magick_effector'
require 'capybara-webkit'
require 'tmpdir'
require 'uri'

module WebShot
  class Renderer
    include Utils

    def initialize
      Capybara::Webkit.configure do |config|
        config.frozen? and next
        config.allow_unknown_urls
        config.ignore_ssl_errors
        config.timeout = 30
        if WebShot.config.proxy
          uri = URI.parse(WebShot.config.proxy)
          proxy_info = {host: uri.host, port: uri.port}
          uri.user     and proxy_info[:user] = uri.user
          uri.password and proxy_info[:pass] = uri.password
          config.use_proxy proxy_info
        end
        logger.debug "Webkit Config: #{config.inspect}"
      end

      @driver = Capybara::Webkit::Driver.new 'webshot', Capybara::Webkit::Configuration.to_hash
      logger.debug 'Initialized'
    end
    attr_reader :driver

    def save_url_to_file(uri, file, width, height)
      driver.visit uri.to_s
      i = 0
      while i < 8
        sleep 0.1 * i
        break if driver.evaluate_script('document.readyState') == "complete"
        i += 1
      end
      driver.execute_script "document.body.style.overflow = 'hidden';"
      driver.save_screenshot file, width: width, height: height, resize_to_contents: false, show_pointer: false
    end

    def render(req)
      logger.info "Rendering, URI= #{req.uri}"
      logger.debug "Render request detail: #{req.to_hash.dup.tap{|r| r.delete(:uri)}.inspect}"
      tmppath = File.join Dir.tmpdir, Dir::Tmpname.make_tmpname('ws-', '.png')
      save_url_to_file req.uri, tmppath, req.winsize_x, req.winsize_y
      img = Magick::Image.read(tmppath)[0]
      File.unlink(tmppath)
      img = MagickEffector.all img, req
      logger.debug "Rendering is completed (#{req.uri})"
      img.to_blob
    end

  end
end
