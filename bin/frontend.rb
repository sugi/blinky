#!/usr/bin/ruby
#
# Blinky - Web site thumbnail service with webkit
#

$: << 'lib'
require 'blinky/version'
require 'blinky/errors'
require 'blinky/storage'
require 'sinatra'
require "sinatra/config_file"
require 'haml'
require 'cgi'
require 'uri'
require 'pathname'
require 'pp'
require 'json'

set :root, (Pathname.new(__FILE__) + '..').dirname

if ENV["RACK_ENV"] == "deployment"
  set :environment, :production
end
conffile = "#{settings.root}/blinky-conf.yml"
File.exists?(conffile) and
  config_file conffile # load setting to set :environment

if development?
  require 'sinatra/reloader'
  set :logging, Logger::DEBUG
  set :dump_errors, true
end

set :server, %w[puma thin unicorn mongrel webrick]

if File.exists?(conffile)
  config_file conffile
  Blinky.read_config_file "#{settings.root}/blinky-conf.yml"
end

SHOT_STORE = Blinky::Storage.new(nil, mq_threaded: false)

before do
  logger.progname = 'WebShopt::Frontend'
end

helpers do
  def h(str)
    CGI.escapeHTML(str.to_s)
  end
  def u(str)
    URI::Parser.new.escape(str.to_s)
  end
end

def fetch
  wreq = Blinky::Request.from_rack request, params
  begin
    wreq.validate!
  rescue Blinky::InvalidURI => e
    logger.warn "Deny invalid URI: '#{wreq.uri}'"
    halt 400, 'Invalid URI'
  rescue Blinky::ForbiddenURI => e
    logger.warn "Deny forbidden URI: '#{wreq.uri}'"
    halt 403, 'Forbidden URI'
  end
  SHOT_STORE.fetch wreq
end

def shot
  ret = fetch
  logger.debug "Shot return: #{ret.to_hash.dup.tap{|r| r.delete(:blob)}.inspect} (blob length=#{ret[:blob].to_s.length})"
  ret[:cache_control] and
    cache_control *[*ret[:cache_control]]
  ret[:etag]  and etag ret[:etag]
  ret[:mtime] and last_modified ret[:mtime]
  if ret[:path]
    send_file ret[:path], type: 'image/png', filename: nil, last_modified: ret[:mtime]
  else
    halt 200, {'Content-Type' => 'image/png'}, ret[:blob]
  end
end

def do_status
  ret = fetch
  ret.delete :blob
  cache_control :no_cache
  content_type "application/json; charset=utf-8"
  ret.to_json
end

get '/show' do
  @uri = params['uri'].to_s.strip
  if @uri.empty?
    @uri = 'https://www.ruby-lang.org/'
  elsif @uri !~ %r{^https?://}
    @uri = "http://#{@uri}"
  end
  cache_control :no_cache
  haml :show
end

get '/shot' do
  shot
end

get '/shot/*' do
  shot
end

get '/status/*' do
  do_status
end

get '/status' do
  do_status
end

get '/usage' do
  haml :usage
end

get '/' do
  cache_control :no_cache
  haml :index
end
