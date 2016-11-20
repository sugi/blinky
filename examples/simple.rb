#!/usr/bin/ruby
#
# Blinky - Web site thumbnail service with webkit
#

require 'blinky'

Blinky.configure do |c|
  c.loglevel = Logger::DEBUG
end

ren = Blinky::Renderer.new
req = Blinky::Request.new uri: ARGV.first || 'http://ruby-lang.org/', imgsize: [400, 400], winsize: [1200, 1600]
File.open('screenshot.png', 'w') do |f|
  f << ren.render(req)
end
puts "Screenshot has been saved to screenshot.png"
