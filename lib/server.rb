export :start

require 'tipi'
require 'oj'
Oj.mimic_JSON
Oj.add_to_json
Oj.default_options = { symbol_keys: true }

DigitalFabric = import 'digital-fabric'
Logger        = import 'logger'

DF_SERVER_PORT = 4646
DF_SERVER_OPTS = {
  reuse_addr: true,
  reuse_port: true,
  dont_linger: true,
  upgrade: {
    df: ->(socket, headers) { DigitalFabric.upgrade_agent(socket, headers) }
  }
}

def start
  server = Tipi.listen('0.0.0.0', DF_SERVER_PORT, DF_SERVER_OPTS)
  Logger.log "Serving on port #{DF_SERVER_PORT}"
  server.each { |r| handle_request(r) }
end

MIME_JSON = 'application/json'
JSON_HEADERS = { 'Content-Type' => MIME_JSON }
STATUS_NOT_FOUND = '404 Not found'

def handle_request(request)
  Logger.log "#{request.method.upcase} #{request.uri}"
  case request.path
  when '/'
    request.respond({'Hi': 'from Digital Fabric'}.to_json, JSON_HEADERS)
  when '/agents'
    agents = DigitalFabric.connected_agents
    request.respond(agents.to_json, JSON_HEADERS)
  when /^\/agents\/([^\/]+)/
    agent_name = Regexp.last_match[1]
    DigitalFabric.route_agent_request(agent_name, request)
  else
    request.respond(nil, ':status' => STATUS_NOT_FOUND)
  end
end
