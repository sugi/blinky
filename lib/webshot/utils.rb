require 'webshot/config'

module WebShot
  module Utils
    def config
      WebShot.config
    end

    def logger
      @logger and return @logger
      @logger = config.logger_class.new(config.logger_out)
      @logger.level = config.loglevel
      @logger.progname = self.class.to_s
      @logger
    end
  end
end
