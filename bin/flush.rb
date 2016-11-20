#!/usr/bin/ruby
require 'blinky/storage'

conffile = File.join(File.dirname(__FILE__), '..', 'blinky-conf.yml')
if File.exists? conffile
  Blinky.read_config_file conffile
end

s = Blinky::Storage.new
s.flush
