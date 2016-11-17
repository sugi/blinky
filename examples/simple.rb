#!/usr/bin/ruby
#
# WebShot - Web site thumbnail service with webkit
#

require 'webshot'

WebShot.configure do |c|
  c.loglevel = Logger::DEBUG
end

ren = WebShot::Renderer.new
req = WebShot::Request.new uri: ARGV.first || 'http://ruby-lang.org/', imgsize: [400, 400], winsize: [1200, 1600]
File.open('screenshot.png', 'w') do |f|
  f << ren.render(req)
end
puts "Screenshot has been saved to screenshot.png"
