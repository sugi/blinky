#!/usr/bin/ruby
require 'webshot/storage'

conffile = File.join(File.dirname(__FILE__), '..', 'webshot-conf.yml')
if File.exists? conffile
  WebShot.read_config_file conffile
end

s = WebShot::Storage.new
s.flush
