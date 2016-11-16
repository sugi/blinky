#!/usr/bin/ruby
require 'webshot'

WebShot.configure do |c|
  c.loglevel = Logger::DEBUG
end

s = WebShot::Storage.new(File.join(Dir.pwd, 'cache'))
s.flush
