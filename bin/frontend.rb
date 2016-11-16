#!/usr/bin/ruby
#
# WebShot - Web site thumbnail service with webkit
#

$: << 'lib'
require 'webshot/version'
require 'webshot/errors'
require 'webshot/storage'
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
config_file "#{settings.root}/webshot-conf.yml" # load setting to set :environment

if development?
  require 'sinatra/reloader'
  set :logging, Logger::DEBUG
  set :dump_errors, true
end

set :server, %w[puma thin unicorn mongrel webrick]

config_file "#{settings.root}/webshot-conf.yml" # load again to override

WebShot.read_config_file "#{settings.root}/webshot-conf.yml"
SHOT_STORE = WebShot::Storage.new

before do
  logger.progname = 'WebShopt::Frontend'
end

helpers do
  def h(str)
    CGI.escapeHTML(str.to_s)
  end
  def u(str)
    URI.escape(str.to_s)
  end
end

def fetch
  wreq = WebShot::Request.from_rack request, params
  begin
    wreq.validate!
  rescue WebShot::InvalidURI => e
    logger.warn "Error: Invalid URI '#{wreq.uri}'"
    halt 400, 'Invalid URI'
  rescue WebShot::ForbiddenURI => e
    halt 403, 'Forbidden URI'
  end
  SHOT_STORE.fetch wreq
end

def shot
  ret = fetch
  logger.debug "Shot return: #{ret.to_hash.dup.tap{|r| r.delete(:blob)}.inspect} (blob length=#{ret[:blob].to_s.length})"
  headers = {
    'Content-Type' => 'image/png',
  }
  ret[:cache_control] and
    cache_control *[*ret[:cache_control]]
  ret[:etag]  and etag ret[:etag]
  ret[:mtime] and last_modified ret[:mtime]
  halt 200, headers, ret[:blob]
end

def do_status
  ret = fetch
  ret[:length] = ret[:blob].to_s.length
  ret.delete :blob
  cache_control :no_cache
  content_type "application/json; charset=utf-8"
  ret.to_json
end

get '/show' do
  @uri = params['uri'].to_s.strip
  if @uri.empty?
    @uri = 'http://ruby-lang.org/'
  elsif @uri !~ %r{^https?://}
    @uri = "http://#{@uri}"
  end
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
  haml :index
end
