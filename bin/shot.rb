#!/usr/bin/ruby
require 'webshot'

conffile = File.join(File.dirname(__FILE__), '..', 'webshot-conf.yml')
if File.exists? conffile
  WebShot.read_config_file conffile
end

storage = WebShot::Storage.new
renderer = WebShot::Renderer.new
logger = WebShot::Utils.new_logger progname: 'ShotWorker'

storage.dequeue do |req|
  Thread.current.abort_on_exception = true
  begin
    storage.push_result req, renderer.render(req)
  rescue => e
    logger.error "Screenshot failed. #{e.message};\n#{e.backtrace.pretty_inspect}"
    storage.push_result req, e.message, true
  end
end
