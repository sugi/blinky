#!/usr/bin/ruby
require 'blinky'

conffile = File.join(File.dirname(__FILE__), '..', 'blinky-conf.yml')
if File.exists? conffile
  Blinky.read_config_file conffile
end
config = Blinky.config

count = 0
reqlimit = config.shot_max_request.to_i != 0 ? config.shot_max_request.to_i : nil
storage = Blinky::Storage.new
logger = Blinky::Utils.new_logger progname: 'ShotWorker'
ret_queue = Queue.new
req_queue = Queue.new

render_threads = []
render_proc = proc { |logger|
  renderer = Blinky::Renderer.new
  while qe = req_queue.pop
    tag, req = qe
    count += 1
    logger.info "Starting process request ##{count}#{reqlimit ? "/#{reqlimit}" : ""} (#{req.uri})"
    begin
      Timeout::timeout((config.webkit_load_timeout * (config.webkit_load_retry + 1) + config.page_complete_timeout) + 10) {
        ret_queue.push [tag, [req, renderer.render(req)]]
      }
    rescue Blinky::URILoadFailed => e
      logger.error "Screenshot FAILED. [#{e.class.to_s}] #{e.message}#{logger.level == Logger::DEBUG ? "\n" + e.backtrace.pretty_inspect : ''}"
      ret_queue.push [tag, [req, e.message, true]]
    rescue Timeout::Error => e
      logger.error "Screenshot FAILED by Timeout. This means system may be in heavy load. Skipping to add result and just drop the request."
    rescue => e
      logger.error "Screenshot FAILED with unknown error, dropping the request. [#{e.class.to_s}] #{e.message}\n#{e.backtrace.pretty_inspect}"
      renderer.renew_driver # for safe
    end
  end
}
(config.shot_concurrency).times do |i|
  tlogger = Blinky::Utils.new_logger progname: "ShotWorker-#{i+1}"
  render_threads << Thread.new(tlogger, &render_proc)
end

ret_thread = Thread.new do
  while qe = ret_queue.pop
    tag, ret = qe
    storage.push_result *ret
    storage.mq_ch_req.ack(tag)
  end
end

accepts = 0
storage.mq_req.subscribe(block: true, manual_ack: true) do |del_info, props, body|
  accepts += 1
  req = Marshal.load(body)
  logger.debug "Accept request ##{accepts} (#{req.uri})"
  req_queue.push([del_info.delivery_tag.to_i, req])
  render_threads.each_with_index do |t, i|
    t.alive? and next
    logger.error "Render thread ##{i+1} was dead!"
    begin
      t.join
    rescue => e
      logger.error "Exception in render thread: #{e.class.to_s}; #{e.message}#{e.backtrace.pretty_inspect}"
    end
    render_threads[i] = Thread.new(Blinky::Utils.new_logger progname: "ShotWorker-#{i+1}", &render_proc)
  end
  if reqlimit && accepts >= reqlimit
    logger.warn "Shot max request has been reached (#{reqlimit}), stop to accept request..."
    render_threads.length.times { req_queue.push nil }
    Thread.exit
  end
end

render_threads.each do |t|
  t.join
end

ret_queue.push nil
ret_thread.join
