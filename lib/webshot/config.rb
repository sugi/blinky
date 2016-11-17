require 'logger'
require 'yaml'

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

    attr_accessor :loglevel, :logger_class, :logger_out,
      :storage_dir, :mq_server, :proxy, :failimage_maxtry
    attr_reader :forbidden_url_pattern

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
      @failimage_maxtry = 3
      @forbidden_url_pattern = nil
    end
  end

  def forbidden_url_pattern=(pat)
    @forbidden_url_pattern =
      if pat.nil? || pat.empty?
        nil
      elsif pat.respond_to?(:match)
        pat
      else
        Regexp.new(pat)
      end
  end

  module_function
  def config
    Config.instance
  end

  def configure(&block)
    Config.modify(&block)
  end

  def read_config_file(path)
    YAML.load_file(path).each do |key, val|
      config.public_send "#{key}=", val
    end
  end
end
