require! <[colors fs moment path request]>

{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_merge, yapps_utils} = global.get-bundled-modules!
{PRETTIZE_KVS} = yapps_utils.debug

{create-tty} = require \./helpers/tty
PROTOCOL = require \./helpers/protocol
{AGENT_EVENT_HTTP_BY_SERVER, AGENT_EVENT_REGISTER_ACKED} = PROTOCOL.events

DUMMY = (dummy) ->
  return 0 if yes
  return 1 if no

const DEFAULT_RESTART_TIMEOUT = 20m       # 20 minutes
const DEFAULT_SESSION_TIMEOUT = 2m        # 2 minutes

const DEFAULT_OPTIONS =
  url: \https://wstty.tic-tac-toe.io
  namespace: \tty
  restart_timeout: DEFAULT_RESTART_TIMEOUT
  session_timeout: DEFAULT_SESSION_TIMEOUT
  lookup_next_server: no

const UNKNOWN_VERSION = \unknown
const PROTOCOL_VERSION = \0.4.0
const PROTOCOL_VERSION_LEGACY = \0.1.0

const AGENT_CONNECTION_INFO_DEFAULTS =
  protocol_version: PROTOCOL_VERSION_LEGACY
  software_version: UNKNOWN_VERSION
  socketio_version: UNKNOWN_VERSION

REGULAR_TERM_CHECK = -> return module.tty.onTermCheck!


class ChannelHandler
  (@ttys, @evt, @name, @context, @func) ->
    @sid = null
    @events = []
    @prefix = "channels[#{evt.magenta}]"
    return

  hook-channel: (s) ->
    {evt, prefix, name} = self = @
    s.on evt, -> return self.process-event.apply self, arguments
    return INFO "#{prefix}: registered by #{name.yellow}"

  process-event: ->
    {evt, name, context, func, prefix} = self = @
    args = Array.from arguments
    args = [evt] ++ args
    try
      func.apply context, args
    catch error
      ERR error, "#{prefix}: failed to process by #{name}"

  cache-event: (args) ->
    {events, prefix} = self = @
    time = new Date! - 0
    xs = {time, args}
    INFO "#{prefix}: server-disconnected, cache one event (#{(JSON.stringify args).gray})"
    return events.push xs

  emit-internally: (args) ->
    {evt, ttys} = self = @
    {socket} = ttys
    xs = [evt] ++ args
    return socket.emit.apply socket, xs

  emit: ->
    {ttys} = self = @
    args = Array.from arguments
    return self.emit-internally args if ttys.connected
    return self.cache-event args

  emit-when-connected: ->
    {prefix, ttys} = self = @
    args = Array.from arguments
    return self.emit-internally args if ttys.connected
    return INFO "#{prefix}: server-disconnected, drop one event (#{(JSON.stringify args).gray})"

  at-server-connected: (@cc) ->
    {sid, events, prefix} = self = @
    {instance_id} = cc
    self.sid = instance_id
    self.events = []
    self.connected = yes
    return unless sid?
    count = events.length
    return if count is 0
    return WARN "#{prefix}: drop #{count.to-string!.red} events because #{sid} != #{instance_id}" unless sid is instance_id
    for ee in events
      {time, args} = ee
      now = new Date! - 0
      duration = "#{now - time}"
      INFO "#{prefix}: re-send event #{duration.cyan}ms ago <= #{(JSON.stringify args).gray}"
      self.emit-internally args



class TTYSocket
  (opts) ->
    self = @
    self.opts = lodash_merge {}, DEFAULT_OPTIONS, opts
    {url, namespace} = opts
    self.paired = no
    self.connected = no
    self.counter = 0
    self.server-url = url
    cc = lodash_merge {}, AGENT_CONNECTION_INFO_DEFAULTS
    self.metadata = {cc}
    self.handlers = {}
    self.transmissions = {tx: 0, rx: 0, flag: no}
    INFO "opts => #{PRETTIZE_KVS self.opts}"

  lookup-server: (done) ->
    {opts, server-url} = self = @
    {cc} = module
    INFO "lookup-server: opts => #{PRETTIZE_KVS opts}"
    {lookup_next_server, namespace} = opts
    return done "lookup-server => select #{server-url.cyan} to use" unless lookup_next_server
    uri = "#{server-url}/api/v1/config"
    json = yes
    body = {cc}
    INFO "lookup-server => query from #{uri.cyan} by posting JSON body: #{PRETTIZE_KVS cc}"
    (err, rsp, body) <- request.post {json, uri, body}
    return done "lookup-server => fallback to use #{server-url.cyan} because of #{err}" if err?
    return done "lookup-server => fallback to use #{server-url.cyan} because of non-200 response code: #{rsp.statusCode} (#{rsp.statusMessage.red})" unless rsp.statusCode is 200
    console.log body
    {data} = body
    return done "lookup-server => fallback to use #{server-url.cyan} because of missing _data_ field in response" unless data?
    {url} = data
    return done "lookup-server => fallback to use #{url.cyan} because of missing _data.url_ field in response" unless url?
    self.server-url = url
    INFO "using #{url.cyan}"
    return done!


  init: (@system-info, done) ->
    {opts, handlers} = self = @
    {url, namespace} = opts
    self.id = system-info.id
    (warning) <- self.lookup-server
    WARN warning if warning?
    {server-url} = self
    full-path = "#{server-url}/#{namespace}"
    io = require \socket.io-client
    s = self.socket = io full-path, {transports: ['websocket']}
    INFO "connecting to #{full-path.cyan} ..."
    INFO "connecting #{full-path} ..."
    s.on \disconnect, -> return self.onDisconnect!
    s.on \err, (buf) -> return self.onErr buf
    s.on \restart_agent, (buf) -> return self.onRestart buf
    s.on \connect, -> return self.onConnect!
    s.on \reconnect, (num) -> return INFO "tty[#{self.id.yellow}] on reconnect (num: #{num})"
    s.on \command, (buf) -> return self.onCommand buf
    s.on \tty, (chunk) -> return self.onWsData chunk
    s.on \connect_error, (err) -> return ERR err, "tty[#{self.id.yellow}] on connect_error"
    s.on \connect_timeout, -> return DBG "tty[#{self.id.yellow}] on connect_timeout"
    s.on \reconnect_attempt, -> return DBG "tty[#{self.id.yellow}] on reconnect_attempt"
    s.on \reconnecting, -> return DBG "tty[#{self.id.yellow}] on reconnecting"
    s.on \reconnect_error, (err) -> return ERR err, "tty[#{self.id.yellow}] on reconnect_error"
    s.on \reconnect_failed, -> DBG "tty[#{self.id.yellow}] on reconnect_failed"
    s.on AGENT_EVENT_REGISTER_ACKED, (metadata) -> return self.onRegisterAcked metadata
    [ (h.hook-channel s) for evt, h of handlers ]
    f = -> return self.onTimeoutCheck!
    self.resetConnectivityTimer!
    self.timer = setInterval f, 1000ms
    return done!


  onDisconnect: ->
    self = @
    cc = lodash_merge {}, AGENT_CONNECTION_INFO_DEFAULTS
    self.metadata = {cc}
    self.connected = no
    self.resetConnectivityTimer!
    INFO "tty[#{@id.yellow}] onDisconnect"


  onConnect: ->
    {id, system-info, socket} = self = @
    {cc} = module
    system = system-info
    reg = {id, system, cc}
    text = JSON.stringify reg
    INFO "tty[#{id.yellow}] onConnect, and submit registration information: #{text.green}"
    socket.emit \register, text
    self.connected = yes
    INFO "tty[#{id.yellow}] registered"
    # [todo] implement timer, to receive register-acked event,
    # if no such event, than fallback to PROTOCOL_VERSION_LEGACY!!


  resetConnectivityTimer: ->
    {opts} = self = @
    {restart_timeout} = opts
    self.connectivity-timeout = restart_timeout * 60
    INFO "reset connectivity timer to #{restart_timeout} minutes"


  checkConnectivityTimeout: ->
    {opts, connectivity-timeout} = self = @
    {restart_timeout} = opts
    self.connectivity-timeout = remaining = connectivity-timeout - 1
    total = restart_timeout * 60
    return {total, remaining}


  onTimeoutCheck: ->
    {connected, opts} = self = @
    return if connected
    {total, remaining} = self.checkConnectivityTimeout!
    return INFO "restart timer #{total - remaining}s / #{total} (since disconnected)" if remaining > 0
    ERR "keep disconnected more than #{total}s, restart wstty-agent"
    return process.exit 19


  getServerUrl: ->
    return @server-url


  addChannelHandler: (evt, name, context, done) ->
    {handlers} = self = @
    ch = handlers[evt]
    return ["#{evt} is already registered!!"] if ch?
    func = context['process_ttys_event']
    return ["<#{evt}> context doesn't have process_ttys_event()"] unless func?
    return ["<#{evt}> context.process_ttys_event is not a function"] unless func instanceof Function
    name = path.basename name
    ch = handlers[evt] = new ChannelHandler self, evt, name, context, func
    return [null, ch]


  onErr: (buf) ->
    @paired = no
    INFO "tty[#{@id.yellow}] onErr: #{buf}"


  onRegisterAcked: (metadata) ->
    {handlers} = self = @
    self.metadata.cc = metadata.cc
    {cc} = metadata
    INFO "tty[#{@id.yellow}] onRegisterAcked => #{JSON.stringify cc}"
    [ (h.at-server-connected cc) for evt, h of handlers ]


  onRestart: (parameters) ->
    @paired = no
    {msg, timer} = parameters
    INFO "tty[#{@id.yellow}] onRestart: #{JSON.stringify parameters}"
    timer = 3000ms unless timer? and \number is typeof timer
    INFO "tty[#{@id.yellow}] onRestart: shall exit within #{timer}ms"
    f = -> process.exit 18
    setTimeout f, timer


  onCommand: (buf) ->
    text = "#{buf}"
    INFO "tty[#{@id.yellow}] onCommand, text = #{text}"
    try
      cmd = JSON.parse text
      return @.requestTTY cmd if cmd.type == "req-tty"
      return @.controlTTY cmd if cmd.type == "ctrl-tty"
      return @.destroyTTY cmd if cmd.type == "destroy-tty"
    catch error
      ERR error, "tty[#{@id.yellow}] onCommand"
      throw error


  onWsData: (chunk) ->
    return WARN "tty[#{@id.yellow}] ws data but it's not paired!!" unless @paired
    bytes = "#{chunk.length}"
    DBG "ws -> pty: #{bytes.green} bytes"
    @term.write chunk
    @counter = 0
    @transmissions.rx = @transmissions.rx + bytes.length
    @transmissions.flag = yes


  onPtyData: (chunk) ->
    return WARN "tty[#{@id.yellow}] pty data but it's not paired!!" unless @paired
    bytes = "#{chunk.length}"
    DBG "pty -> ws: #{bytes.green} bytes"
    @socket.emit \tty, chunk
    @counter = 0
    @transmissions.tx = @transmissions.tx + bytes.length
    @transmissions.flag = yes


  onPtyExit: (code, signal) ->
    INFO "tty[#{@id.yellow}] pty exit: #{code}, signal: #{signal}"
    @socket.emit \depair, JSON.stringify {code: code, signal: signal}
    @paired = no
    @term.removeAllListeners \exit
    @term.removeAllListeners \data
    @term = {}


  requestTTY: (cmd) ->
    {socket} = self = @
    return socket.emit \err, "already paired with other web-socket" if @paired
    {params} = cmd
    t = self.term = create-tty params
    return socket.emit \err, "unsupported type of TTY: #{JSON.stringify params}" unless t?
    INFO "tty[#{@id.yellow}] inform wstty server that PTY is ready"
    socket.emit \pair, ""
    self.paired = yes
    t.on \exit, (code, signal) -> return self.onPtyExit code, signal
    t.on \data, (data) -> return self.onPtyData data


  controlTTY: (cmd) ->
    return WARN "tty[#{@id.yellow}] request to control but no paired TTY" unless @paired
    INFO "tty[#{@id.yellow}] controlTTY"
    {params} = cmd
    return @term.control params


  destroyTTY: (cmd) ->
    return WARN "tty[#{@id.yellow}] request to destroy but no paired TTY" unless @paired
    INFO "tty[#{@id.yellow}] destroyTTY"
    @term.destroy!


  onTermCheck: ->
    {paired, opts, counter, transmissions} = self = @
    return true unless paired
    self.counter = counter + 1
    if self.counter > opts.session_timeout * 60
      WARN "tty[#{self.id.yellow}] timeout, destroy TTY"
      self.term.destroy!
      self.counter = 0
    else
      {rx, tx, flag} = transmissions
      transmissions.flag = no
      return INFO "tty[#{self.id.yellow}]: session timer (#{opts.session_timeout * 60}s) => #{self.counter}s, tx/rx: #{tx}/#{rx} bytes" if flag 
      return INFO "tty[#{self.id.yellow}]: session timer (#{opts.session_timeout * 60}s) => #{self.counter}s"



module.exports = exports =
  attach: (opts, helpers) ->
    module.tty = @tty = new TTYSocket opts
    module.opts = opts
    return

  init: (done) ->
    {system-info, tty} = app = @
    {opts} = module
    {app-package-json} = opts
    return done new Error "#{exports.name.gray} depends on plugin #{'system-info'.yellow} but missing" unless system-info?

    {instance_id} = sys = system-info.to-json!
    protocol_version = PROTOCOL_VERSION
    software_version = app-package-json.version
    socketio_version = global.get-external-module-version \socket.io-client
    module.cc = {protocol_version, software_version, socketio_version, instance_id} # connection-context
    INFO "running with Protocol #{protocol_version.yellow} on socket.io-client #{socketio_version.red}..."

    setInterval REGULAR_TERM_CHECK, 1000ms

    ttt = system-info.to-json!
    (err) <- tty.init ttt
    ERR err "initialization failure" if err?
    return done err

