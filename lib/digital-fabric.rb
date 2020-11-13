export :upgrade_agent, :route_agent_request, :connected_agents

Logger = import 'logger'

UPGRADE_RESPONSE = <<~HTTP.gsub("\n", "\r\n")
HTTP/1.1 101 Switching Protocols
Upgrade: df
Connection: Upgrade

HTTP

@agents = {}

def upgrade_agent(socket, headers)
  agent_name = headers['DF-Agent']
  socket << UPGRADE_RESPONSE
  run_agent_proxy(agent_name, socket)
rescue IOError
  # ignore
end

MIME_JSON = 'application/json'

STATUS_METHOD_NOT_ALLOWED = '405 Method not allowed'
STATUS_INTERNAL_SERVER_ERROR = '500 Internal server error'
STATUS_SERVICE_UNAVAILABLE = '503 Service unavailable'
STATUS_GATEWAY_TIMEOUT = '504 Gateway timeout'

def route_agent_request(agent_name, request)
  agent = @agents[agent_name]
  return request.respond(nil, ':status' => STATUS_SERVICE_UNAVAILABLE) if agent.nil?

  payload = agent_request_payload_from_http_request(request)
  return request.respond(nil, ':status' => STATUS_METHOD_NOT_ALLOWED) if payload.nil?

  cancel_after(60) do
    agent << { kind: 'request', sender: Fiber.current, payload: payload }
    response = receive
    payload = response[:payload]
    request.respond(payload.to_json, 'Content-Type' => MIME_JSON)
  end
rescue Polyphony::Cancel
  request.respond(nil, ':status' => STATUS_GATEWAY_TIMEOUT)
rescue => e
  Logger.log("Error while waiting for reply: #{e.inspect} #{e.backtrace.inspect}")
  request.respond(e.message, ':status' => STATUS_INTERNAL_SERVER_ERROR)
end

def connected_agents
  @agents.keys
end

def agent_request_payload_from_http_request(request)
  case request.method.upcase
  when 'GET'
    request.query
  when 'POST'
    body = request.body
    body && (Oj.load(body) rescue nil)
  else
    nil
  end
end

def run_agent_proxy(agent_name, socket)
  proxy = start_proxy_fiber(agent_name, socket)
  @agents[agent_name] = proxy
  incoming_socket_loop(agent_name, socket, proxy)
ensure
  @agents.delete(agent_name)
end

def start_proxy_fiber(agent_name, socket)
  iseq = 0
  pending_requests = {}
  spin_loop do
    message = receive
    case message[:kind]
    when 'response'
      pending = pending_requests[message[:iseq]]
      if pending
        pending[:sender] << message
        pending_requests.delete(message[:iseq])
      end
    when 'request'
      message[:iseq] ||= (iseq += 1)
      pending_requests[message[:iseq]] = message
      socket_request = {
        kind: 'request',
        iseq: message[:iseq],
        payload: message[:payload]
      }
      socket << "#{socket_request.to_json}\n"
    end
  end
end

def incoming_socket_loop(agent_name, socket, proxy)
  loop do
    while (message = socket.gets)
      message = Oj.load(message) rescue nil
      handle_incoming_socket_message(agent_name, message, proxy) if message
    end
  end
rescue IOError
  # ignore
end

def handle_incoming_socket_message(agent_name, message, proxy)
  case message[:kind]
  when 'response'
    proxy << message
  when 'log'
    log_message = format('[%s] %s', agent_name, message[:payload])
    Logger.log(log_message)
  end
end
