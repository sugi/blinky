require 'logger'

module WebShot
  class Config
    class << self
      def modify
        yield instance
      end

      def instance
        @instance ||= new
      end
    end

    attr_accessor :loglevel
    attr_accessor :logger_class
    attr_accessor :logger_out
    attr_accessor :storage_dir
    attr_accessor :mq_server
    attr_accessor :proxy

    def initialize
      @loglevel = Logger::INFO
      @logger_class = Logger
      @logger_out = $stderr
      @storage_dir = File.join(Dir.pwd, 'cache')
      @mq_server = ENV['AMQ_URI'] || "amqp://guest:guest@localhost:5672"
      @proxy = nil
      if ENV['http_proxy'] && !ENV['http_proxy'].empty?
        @proxy = ENV['http_proxy']
      end
    end
  end

  module_function
  def config
    Config.instance
  end

  def configure(&block)
    Config.modify(&block)
  end
end
