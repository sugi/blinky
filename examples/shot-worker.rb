#!/usr/bin/ruby
require 'webshot'
require 'pp'

WebShot.configure do |c|
  c.loglevel = Logger::DEBUG
end

storage = WebShot::Storage.new
renderer = WebShot::Renderer.new

storage.dequeue(true) do |req|
  begin
    storage.push_result(req, renderer.render(req))
  rescue => e
    pp e.backtrace
    raise e
  end
end
