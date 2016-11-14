#!/usr/bin/ruby
require 'webshot'
require 'pp'

WebShot.configure do |c|
  c.loglevel = Logger::DEBUG
end

s = WebShot::Storage.new(File.join(Dir.pwd, 'cache'))

ARGV.each do |uri|
  req = WebShot::Request.new uri: uri, imgsize: [800, 800], winsize: [128, 128]
  s.fetch(req, true)
end

