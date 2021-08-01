require! <[prettyjson semver request serialize-error]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_findIndex, lodash_merge} = global.get-bundled-modules!
PROTOCOL = require \../helpers/protocol
{AGENT_EVENT_HTTP_BY_SERVER} = PROTOCOL.events
{HTTP_INVALID_REQUEST, HTTP_REQUEST_ERROR, PROGRESS_EVENT_ACKED} = PROTOCOL.constants


const DEFAULT_HTTP_MONITOR_TIMEOUT = 120s
const DEFAULT_HTTP_REQUEST_TIMEOUT = 60s

const DEFAULT_OPTS =
  v1:
    request_timeout: DEFAULT_HTTP_REQUEST_TIMEOUT
    monitor_timeout: DEFAULT_HTTP_MONITOR_TIMEOUT


SERIALIZE_ERROR = (err) ->
  xs = serialize-error err
  xs.stack = xs.stack.split '\n'
  return xs



class V1_Task
  (@manager, @id, @uri, @parameters) ->
    @start-time = (new Date!) - 0
    @prefix = "#{AGENT_EVENT_HTTP_BY_SERVER}/#{id.yellow}"
    {v1} = manager.opts
    @request_timeout = v1.request_timeout
    @monitor_timeout = v1.monitor_timeout
    @timeout = 0
    @running = no
    return

  feedback-error: (name, message, err=null) ->
    {manager, id, prefix} = self = @
    WARN "#{prefix}: feedback-error => #{name}/#{message} => #{err}"
    self.running = no
    manager.remove-task id
    manager.feedback-error id, name, message, err

  feedback-result: (result, size, type) ->
    {manager, id, prefix} = self = @
    # INFO "#{prefix}: feedback-result => #{type} => #{size} bytes"
    self.running = no
    manager.remove-task id
    manager.feedback-result id, result

  feedback-progress: (evt, percentage=0) ->
    {manager, id, prefix} = self = @
    INFO "#{prefix}: feedback-progress => #{evt}/#{percentage}"
    manager.feedback-progress id, evt, percentage

  start: ->
    {id, uri, parameters, prefix, request_timeout, monitor_timeout} = self = @
    return self.feedback-error \HTTP_INVALID_REQUEST, "missing parameters!!" unless parameters?
    return self.feedback-error \HTTP_INVALID_REQUEST, "missing uri!!" unless uri?
    {method, query, body, json} = parameters
    return self.feedback-error \HTTP_INVALID_REQUEST, "missing parameter: method" unless method?
    return self.feedback-error \HTTP_INVALID_REQUEST, "missing parameter: json" unless json?
    timeout = request_timeout * 1000ms
    opts = self.opts = {method, json}
    opts['qs'] = query if query? and Object.keys(query).length isnt 0
    opts['body'] = body if body? and Object.keys(body).length isnt 0
    INFO "#{prefix}: requesting => #{uri.cyan} => #{(JSON.stringify opts).gray}"
    opts <<< {timeout, uri}
    self.feedback-progress PROGRESS_EVENT_ACKED
    self.timeout = monitor_timeout
    self.running = yes
    (err, rsp, body) <- request opts
    return ERR "#{prefix}: got response but already timeout => #{err}, #{JSON.stringify rsp}, #{JSON.stringify body}" unless self.running
    return self.feedback-error \HTTP_REQUEST_ERROR, "request error", err if err?
    {headers, httpVersion, method, statusCode, statusMessage} = rsp
    now = new Date!
    duration = now - self.start-time
    result = {headers, httpVersion, method, statusCode, statusMessage, body, duration}
    size = headers['content-length']
    type = headers['content-type']
    INFO "#{prefix}: #{uri} responses => #{type} => #{size} bytes"
    return self.feedback-result result, size, type

  at-check: ->
    {prefix, running, timeout, uri, monitor_timeout} = self = @
    return unless running
    return WARN "#{prefix} timeout value is unexpected: #{timeout}" unless timeout > 0
    self.timeout = timeout - 1
    return INFO "#{prefix}: waiting #{uri.cyan} (#{self.timeout} seconds ...)" if self.timeout > 0
    INFO "#{prefix}: timeout!!"
    self.feedback-error \HTTP_BY_AGENT_ERR_AGENT_TIMEOUT, "http request takes more than #{monitor_timeout}s"



class ServiceManager
  (@configs, @app) ->
    self = @
    @tasks = {}
    @handler = null
    @opts = lodash_merge {}, DEFAULT_OPTS, configs
    {request_timeout, monitor_timeout} = @opts.v1
    INFO "request_timeout: #{request_timeout}s"
    INFO "monitor_timeout: #{monitor_timeout}s"

  init: (@tty-socket, done) ->
    INFO "init"
    {app} = self = @
    [err, handler] = tty-socket.addChannelHandler AGENT_EVENT_HTTP_BY_SERVER, __filename, self
    return done err if err?
    self.handler = handler
    # return done "failed to register event #{AGENT_EVENT_HTTP_BY_SERVER}" unless handler?
    f = -> return self.at-timeout!
    self.timer = setInterval f, 1000ms
    return done!

  feedback: (id, progress, result, error) ->
    {handler} = self = @
    # INFO "feedback: AGENT_EVENT_HTTP_BY_SERVER/#{id} => progress: #{JSON.stringify progress}"
    # INFO "feedback: AGENT_EVENT_HTTP_BY_SERVER/#{id} => result: #{JSON.stringify result}"
    # INFO "feedback: AGENT_EVENT_HTTP_BY_SERVER/#{id} => error: #{JSON.stringify error}"
    handler.emit id, progress, result, error

  feedback-progress: (id, evt, percentage=0) ->
    progress = {evt, percentage}
    return @.feedback id, progress, null, null

  feedback-error: (id, name, message, error=null) ->
    {constants} = PROTOCOL
    code = constants[name]
    code = -1 unless code?
    err = {name, code, message}
    err['err'] = SERIALIZE_ERROR error if error?
    # INFO "#{name} => #{JSON.stringify err}"
    return @.feedback id, null, null, err

  feedback-result: (id, result) ->
    return @.feedback id, null, result, null

  remove-task: (id) ->
    delete @tasks[id]

  at-timeout: ->
    {tasks} = self = @
    [ (task.at-check!) for id, task of tasks ]
    return

  process_ttys_event: (evt, request-version, request-id, url, parameters) ->
    {tasks} = self = @
    return self.feedback-error request-id, HTTP_INVALID_REQUEST, "unsupported request: #{request-version}" unless request-version is \v1
    t = tasks[request-id] = new V1_Task self, request-id, url, parameters
    t.start!




module.exports = exports =
  attach: (opts, helpers) ->
    module.helpers = helpers
    module.sm = @agent-http-service = new ServiceManager opts, @

  init: (done) ->
    {sm} = module
    {tty} = app = @
    return done new Error "service-http depends on plugin #{'tty'.yellow} but missing" unless tty?
    return sm.init tty, done

