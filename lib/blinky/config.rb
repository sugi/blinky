require 'logger'
require 'yaml'

module Blinky
  class Config
    class << self
      def modify
        yield instance
      end

      def instance
        @instance ||= new
      end
    end # class << self

    attr_accessor :loglevel, :logger_class, :logger_out,
    :storage_dir, :amq_uri, :proxy_uri, :failimage_maxtry,
    :webkit_max_request, :webkit_renew_sleep, :webkit_crash_retry,
    :webkit_load_timeout, :shot_max_request, :queue_refresh_time,
    :image_refresh_time, :webkit_load_retry, :page_complete_timeout,
    :queue_request_prefetch, :queue_result_prefetch
    attr_reader :forbidden_url_pattern

    def initialize
      @logger_class = Logger
      @logger_out = $stderr

      {
        loglevel: Logger::INFO,
        storage_dir: File.join(Dir.pwd, 'cache'),
        amq_uri: "amqp://guest:guest@localhost:5672",
        proxy_uri: nil,
        failimage_maxtry: 5,
        webkit_max_request: 50,
        webkit_crash_retry: 3,
        webkit_load_timeout: 30,
        webkit_load_retry: 1,
        page_complete_timeout: 10,
        shot_max_request: 300,
        forbidden_url_pattern: %r{^https?://(?:[^.]+$|10\.|172\.(?:1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|0\.|169\.254\.|2(?:2[4-9]|[3-5][0-9])\.)},
        queue_refresh_time: 3 * 3600,
        image_refresh_time: 3 * 24 * 3600,
        queue_request_prefetch: 10,
        queue_result_prefetch: 1024,
      }.each do |key, default|
        envkey = "BL_#{key.upcase}"
        if ENV[envkey].nil? || ENV[envkey].empty?
          public_send "#{key}=", default
        else
          public_send "#{key}=", default.kind_of?(Fixnum) ? ENV[envkey].to_i : ENV[envkey]
        end
      end

      # fallback environment keys
      {
        proxy_uri: 'http_proxy',
      }.each do |key, envkey|
        ENV["BL_#{key.upcase}"] and next
        ENV[envkey] or next
        ENV[envkey].empty? and next
        public_send "#{key}=", ENV[envkey]
      end
    end

    def forbidden_url_pattern=(pat)
      @forbidden_url_pattern =
        if pat.respond_to?(:match)
          pat
        elsif pat.nil? || pat.empty?
          nil
        else
          Regexp.new(pat.to_s)
        end
    end
  end # Config class

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
