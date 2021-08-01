require! <[path fs zlib url]>
require! <[byline through request]>
{spawn} = require \child_process
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_findIndex, lodash_merge, mkdirp, moment} = global.get-bundled-modules!
PROTOCOL = require \../helpers/protocol
{MERGE_TEMPLATE, SERIALIZE_ERROR} = require \../helpers/common
{AGENT_EVENT_BASH_BY_SERVER} = PROTOCOL.events
{BASH_INVALID_REQUEST, BASH_REQUEST_ERROR, PROGRESS_EVENT_ACKED, PROGRESS_EVENT_INDICATED} = PROTOCOL.constants

const NAME = \bash-by-server

const DEFAULT_BASH_MONITOR_TIMEOUT = 120s
const DEFAULT_BASH_REQUEST_TIMEOUT = 60s        # useless in `bash-by-server`

const DEFAULT_OPTS =
  v1:
    request_timeout: DEFAULT_BASH_REQUEST_TIMEOUT
    monitor_timeout: DEFAULT_BASH_MONITOR_TIMEOUT


class V1_Task
  (@manager, @workdir, @id, @parameters, @configs, @callback) ->
    @prefix = "#{id}"
    {request_timeout, monitor_timeout} = manager.opts.v1
    @request_timeout = request_timeout
    @monitor_timeout = monitor_timeout
    @timeout = 0
    @running = no
    @logger = null
    return

  feedback-error: (name, message, err=null) ->
    {manager, id, prefix} = self = @
    WARN "#{prefix}: feedback-error => #{name}/#{message} => #{err}"
    self.running = no
    manager.remove-task id
    manager.feedback-error id, name, message, err

  feedback-result: (result) ->
    {manager, id, prefix} = self = @
    self.running = no
    manager.remove-task id
    manager.feedback-result id, result

  feedback-progress: (evt, percentage=0, args=[], lossless=yes) ->
    {manager, id, prefix} = self = @
    DBG "#{prefix}: feedback-progress => #{evt}/#{percentage} => args: #{JSON.stringify args}"
    manager.feedback-progress id, evt, percentage, args, lossless

  start: ->
    {manager, id, parameters, configs, prefix, workdir, monitor_timeout} = self = @
    return self.feedback-error \BASH_INVALID_REQUEST, "missing parameters!!" unless parameters?
    INFO "#{prefix}: requesting => parameters: #{(JSON.stringify parameters).gray}"
    INFO "#{prefix}: requesting => configs: #{(JSON.stringify configs).gray}"
    {command, args, options} = parameters
    return self.feedback-error \BASH_INVALID_REQUEST, "missing parameter: command" unless command?
    WSTTY_AGENT_UNIXSOCK = manager.ctrl-sock
    WSTTY_AGENT_UNIXSOCK_PREFIX = "plugin\t#{NAME}\t#{id}"
    env = {WSTTY_AGENT_UNIXSOCK, WSTTY_AGENT_UNIXSOCK_PREFIX}
    INFO "#{prefix}: requesting <= default env <= #{(JSON.stringify env).gray}"
    opts = lodash_merge {}, options
    opts['env'] = lodash_merge {}, process.env, opts.env, env
    opts['cwd'] = '/tmp' unless opts['cwd']?
    opts['shell'] = yes unless opts['shell']?
    now = moment!
    self.feedback-progress PROGRESS_EVENT_ACKED
    self.timeout = monitor_timeout
    self.filepath = filepath = "#{workdir}#{path.sep}#{now.format 'MMDD'}#{path.sep}#{now.format 'HHmm'}_#{id}.log"
    dir = path.dirname filepath
    INFO "#{prefix}: execution logging stream => #{filepath.yellow}"

    WRITE_STDOUT = (data) ->
      self.at-child-data \stdout, data
      return @.queue data

    WRITE_STDERR = (data) ->
      self.at-child-data \stderr, data
      return @.queue data

    END = -> return @.queue null

    (err) <- mkdirp dir
    return self.feedback-error \BASH_BY_SERVER_ERR_AGENT_NO_LOGGING_STREAM, "failed to create directory #{dir}", err if err?
    stdout-through = through WRITE_STDOUT, END
    stderr-through = through WRITE_STDERR, END
    self.stream = fs.createWriteStream filepath, {encoding: \utf8, autoClose: yes}
    self.stdout-reader = byline.createStream stdout-through
    self.stderr-reader = byline.createStream stderr-through
    self.stdout-reader.on \data, (line) -> return self.at-child-line \stdout, line
    self.stderr-reader.on \data, (line) -> return self.at-child-line \stderr, line
    self.running = yes
    INFO "#{prefix}: running #{command.cyan} with #{JSON.stringify args}"
    child = self.child = spawn command, args, opts
    pid = child.pid.toString!
    self.prefix = "#{prefix}:#{pid.yellow}"
    child.stdout.pipe stdout-through
    child.stderr.pipe stderr-through
    child.on \error, (err) -> return self.at-child-error err
    child.on \exit, (code) -> return self.at-child-end code
    self.write-log \env, manager.ttt
    self.write-log \params, parameters
    self.write-log \configs, configs
    self.start-time = (new Date!) - 0
    self.write-log \start, {}

  write-log: (type, x, close=no) ->
    {prefix, id, stream, filepath, configs, callback} = self = @
    {operation} = configs
    operation = \default unless operation?
    return unless stream?
    t = (new Date!) - 0
    t = t.toString!
    x = x.toString \hex if Buffer.isBuffer x
    x = JSON.stringify x if \object is typeof x
    x = x.toString! unless \string is typeof x
    xs = [t, type, x]
    xs = "#{xs.join '\t'}\n"
    stream.write xs
    return unless close
    self.stream = null
    (none) <- stream.end
    INFO "#{prefix}: #{filepath} <= flushed"
    return INFO "#{prefix}: #{filepath} <= no callback to notify" unless callback?
    return self.manager.upload-archive prefix, id, operation, filepath, callback

  at-child-line: (std, line) ->
    {prefix} = self = @
    line = line.toString!
    return INFO "#{prefix}: <stdout> #{line.gray}" if std is \stdout
    return WARN "#{prefix}: <stderr> #{line.magenta}"

  at-child-data: (std, buffer) ->
    DBG "#{@prefix}: #{std} => #{buffer.length} bytes"
    return @.write-log std, buffer

  at-child-error: (err) ->
    s = SERIALIZE_ERROR err
    WARN "#{@prefix}: err => #{JSON.stringify s}"
    return @.write-log \error, s

  at-child-end: (code) ->
    {prefix, running, start-time} = self = @
    return INFO "#{@prefix}: exit (#{c}) after SIGTERM" unless running
    c = code.toString!
    c = if code is 0 then c.green else c.red
    now = (new Date!) - 0
    duration = "#{now - start-time}"
    INFO "#{prefix}: exit (#{c}), duration: #{duration.cyan}ms"
    result = {code, duration}
    self.running = no
    self.feedback-result result
    return self.write-log \end, result, yes

  at-unixsock-ctrl: (args) ->
    {prefix} = self = @
    DBG "#{prefix}: unixsock-ctrl: args => #{JSON.stringify args}"
    return unless args.length >= 1
    [p, ...argv] = args
    progress = parseInt p
    return WARN "#{prefix}: unixsock-ctrl: invalid progress number: #{p.red}" if progress === NaN
    self.feedback-progress PROGRESS_EVENT_INDICATED, progress, argv, no

  at-check: ->
    {prefix, running, child, timeout, monitor_timeout, parameters} = self = @
    return unless running
    return WARN "#{prefix} timeout value is unexpected: #{timeout}" unless timeout > 0
    self.timeout = timeout - 1
    return DBG "#{prefix}: waiting for `#{parameters.command.cyan}` (#{self.timeout} seconds ...)" if self.timeout > 0
    INFO "#{prefix}: timeout!!"
    self.feedback-error \BASH_BY_SERVER_ERR_AGENT_TIMEOUT, "bash request takes more than #{monitor_timeout}s"
    self.running = no
    child.stdin.end!
    #
    # [todo] Figure out better way to kill all child proces and its descendants, portable way on both Mac OS X and Linux
    #
    # - https://github.com/nodejs/node-v0.x-archive/issues/1811
    # - https://github.com/nodejs/help/issues/1389
    # - https://github.com/Microsoft/node-pty/blob/master/src/unixTerminal.ts#L220
    # - https://github.com/nodejs/node/issues/3617
    #
    child.kill \SIGTERM
    child.kill \SIGKILL
    /*
    try
      INFO "#{prefix}: killing #{-child.pid}, current process pid is #{process.pid}"
      process.kill -child.pid, 'SIGTERM'   # kill the process group of this child. Inspired by https://azimi.me/2014/12/31/kill-child_process-node-js.html
      process.kill -child.pid, 'SIGKILL'
    catch error
      ERR error, "#{prefix}: failed to kill child."
    */
    self.write-log \timeout, {monitor_timeout}, yes



class ServiceManager
  (@configs, @app) ->
    self = @
    @tasks = {}
    @handler = null
    @opts = lodash_merge {}, DEFAULT_OPTS, configs
    tokens = url.parse @opts.app-ctrl-sock
    @ctrl-sock = tokens.path
    {request_timeout, monitor_timeout} = @opts.v1
    INFO "request_timeout: #{request_timeout}s"
    INFO "monitor_timeout: #{monitor_timeout}s"
    INFO "ctrl-sock: #{@ctrl-sock.yellow}"

  init: (@si, @ps, @ttysock, done) ->
    {app} = self = @
    f = -> return self.at-timeout!
    {id, ttt} = json = si.to-json!
    return done "missing id" unless id?
    @id = id
    @ttt = ttt
    return done "missing ttt" unless ttt?
    {profile} = ttt
    return done "missing profile" unless profile?
    self.profile = profile
    self.url = ttysock.getServerUrl!
    self.workdir = workdir = ps.get-app-dir NAME
    (mkdirp-err) <- mkdirp workdir
    return done mkdirp-err if mkdirp-err?
    INFO "init: #{workdir.yellow} is created successfully"
    [reg-err, handler] = ttysock.addChannelHandler AGENT_EVENT_BASH_BY_SERVER, __filename, self
    return done reg-err if reg-err?
    self.handler = handler
    self.timer = setInterval f, 1000ms
    return done!

  feedback: (tid, progress, result, error, lossless=yes) ->
    {handler} = self = @
    # INFO "feedback: AGENT_EVENT_BASH_BY_SERVER/#{tid} => progress: #{JSON.stringify progress}"
    # INFO "feedback: AGENT_EVENT_BASH_BY_SERVER/#{tid} => result: #{JSON.stringify result}"
    # INFO "feedback: AGENT_EVENT_BASH_BY_SERVER/#{tid} => error: #{JSON.stringify error}"
    return handler.emit tid, progress, result, error if lossless
    return handler.emit-when-connected tid, progress, result, error

  feedback-progress: (tid, evt, percentage=0, args=null, lossless=yes) ->
    progress = {evt, percentage}
    progress['args'] = args if args? and Array.isArray args
    return @.feedback tid, progress, null, null, lossless

  feedback-error: (tid, name, message, error=null) ->
    {constants} = PROTOCOL
    code = constants[name]
    code = -1 unless code?
    err = {name, code, message}
    err['err'] = SERIALIZE_ERROR error if error?
    # INFO "#{name} => #{JSON.stringify err}"
    return @.feedback tid, null, null, err

  feedback-result: (tid, result) ->
    return @.feedback tid, null, result, null

  upload-archive: (prefix, tid, operation, filepath, callback) ->
    {profile, id, url} = self = @
    (read-err, raw) <- fs.readFile filepath
    return ERR read-err, "failed to read #{filepath}" if read-err?
    INFO "#{prefix}: #{filepath} is read => #{raw.length} bytes"
    (compress-err, data) <- zlib.gzip raw
    return ERR compress-err, "failed to compress #{filepath}" if compress-err?
    INFO "#{prefix}: #{filepath} is compressed => #{data.length} bytes"
    filename = "execution-log"
    pathname = "/api/v1/upload-archive/#{profile}/#{id}/#{NAME}"
    uri = "#{url}#{pathname}"
    method = \POST
    target = callback
    task = tid
    qs = {operation, task, target}
    archive = value: data, options: {filename}
    formData = {archive}
    x = {uri, method, qs}
    INFO "#{prefix}: posting #{(JSON.stringify x).gray}"
    opts = {uri, method, qs, formData}
    (err, rsp, body) <- request opts
    return ERR err, "failed to post to #{uri}" if err?
    return ERR "failed to post to #{uri} because of non-200 response code: #{rsp.statusCode} (#{rsp.statusMessage.red})" unless rsp.statusCode is 200
    return INFO "successfully to upload to #{uri}"

  remove-task: (id) ->
    delete @tasks[id]

  at-timeout: ->
    {tasks} = self = @
    [ (task.at-check!) for id, task of tasks ]
    return

  at-unixsock-ctrl: (id, args) ->
    {tasks} = self = @
    t = tasks[id]
    return t.at-unixsock-ctrl args if t?
    return WARN "no such task #{id} to process the control command: #{JSON.stringify args}"

  process_ttys_event: (evt, request-version, request-id, parameters, configs, callback) ->
    {workdir, tasks} = self = @
    return self.feedback-error request-id, BASH_INVALID_REQUEST, "unsupported request: #{request-version}" unless request-version is \v1
    parameters = MERGE_TEMPLATE parameters
    t = tasks[request-id] = new V1_Task self, workdir, request-id, parameters, configs, callback
    t.start!



module.exports = exports =
  attach: (opts, helpers) ->
    app = @
    module.helpers = helpers
    module.sm = app.agent-bash-service = new ServiceManager opts, app

  init: (done) ->
    {sm} = module
    {system-info, ps, tty} = app = @
    return done new Error "service-bash depends on plugin #{'system-info'.yellow} but missing" unless system-info?
    return done new Error "service-bash depends on plugin #{'ps'.yellow} but missing" unless ps?
    return done new Error "service-bash depends on plugin #{'tty'.yellow} but missing" unless tty?
    return sm.init system-info, ps, tty, done

  ctrl: (id, ...args) ->
    return module.sm.at-unixsock-ctrl id, args

