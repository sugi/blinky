#!/usr/bin/ruby
require 'blinky'
require 'pp'

Blinky.configure do |c|
  c.loglevel = Logger::DEBUG
end

s = Blinky::Storage.new(File.join(Dir.pwd, 'cache'))

ARGV.each do |uri|
  req = Blinky::Request.new uri: uri, imgsize: [800, 800], winsize: [128, 128]
  s.fetch(req, true)
end

