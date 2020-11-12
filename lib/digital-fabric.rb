export :start

require 'tipi'
require 'json'

DF_SERVER_PORT = 4646
DF_SERVER_OPTS = { reuse_addr: true, reuse_port: true, dont_linger: true }

def start
  server = Tipi.listen('0.0.0.0', DF_SERVER_PORT, DF_SERVER_OPTS)
  log "Serving on port #{DF_SERVER_PORT}"
  server.each { |r| handle_request(r) }
end

MIME_JSON = 'application/json'

def handle_request(request)
  log "#{request.method.upcase} #{request.uri}"
  request.respond({hello: 'world'}.to_json, 'Content-Type' => MIME_JSON)
end

def log(msg)
  puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{msg}"
end