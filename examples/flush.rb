#!/usr/bin/ruby
require 'blinky'

Blinky.configure do |c|
  c.loglevel = Logger::DEBUG
end

s = Blinky::Storage.new(File.join(Dir.pwd, 'cache'))
s.flush
