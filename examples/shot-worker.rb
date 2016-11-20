#!/usr/bin/ruby
require 'blinky'
require 'pp'

Blinky.configure do |c|
  c.loglevel = Logger::DEBUG
end

storage = Blinky::Storage.new
renderer = Blinky::Renderer.new

storage.dequeue(true) do |req|
  begin
    storage.push_result(req, renderer.render(req))
  rescue => e
    pp e.backtrace
    raise e
  end
end
