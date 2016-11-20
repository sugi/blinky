require 'blinky/config'

module Blinky
  module Utils
    def config
      Blinky.config
    end

    def logger
      @logger and return @logger
      @logger = Utils.new_logger(progname: self.class.to_s)
    end

    module_function
    def new_logger(opts = {})
      conf = Blinky.config
      logger = conf.logger_class.new(conf.logger_out)
      {
        level: conf.loglevel,
        progname: 'Blinky',
      }.merge(opts).each do |key, val|
        logger.public_send "#{key}=", val
      end
      logger
    end
  end
end
