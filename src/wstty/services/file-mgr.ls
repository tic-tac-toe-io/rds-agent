require! <[path fs zlib url crypto]>
require! <[byline through request]>
{spawn} = require \child_process
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_findIndex, lodash_merge, lodash_camelCase, mkdirp, moment, async, handlebars} = global.get-bundled-modules!
PROTOCOL = require \../helpers/protocol
{MERGE_TEMPLATE, SERIALIZE_ERROR} = require \../helpers/common
{AGENT_EVENT_FILE_MANAGER} = PROTOCOL.events
{FILEMGR_INVALID_REQUEST, PROGRESS_EVENT_ACKED, PROGRESS_EVENT_INDICATED} = PROTOCOL.constants

const NAME = \file-mgr

const DEFAULT_FILEMGR_MONITOR_TIMEOUT = 120s
const DEFAULT_FILEMGR_REQUEST_TIMEOUT = 60s        # useless in `file-mgr`

const DEFAULT_OPTS =
  v1:
    request_timeout: DEFAULT_FILEMGR_REQUEST_TIMEOUT
    monitor_timeout: DEFAULT_FILEMGR_MONITOR_TIMEOUT


/*
# For nodejs v10.10 (https://nodejs.org/docs/latest-v10.x/api/fs.html#fs_fs_readdir_path_options_callback)
#
class StatFile
  (@dir, @dirent) ->
    @name = dirent.name

  stat: (done) ->
    {dir, name} = self = @
    return done!

  to-json: ->
    {dir, dirent, name} = self = @
    is_block_device = dirent.isBlockDevice!
    is_character_device = dirent.isCharacterDevice!
    is_directory = dirent.isDirectory!
    is_fifo = dirent.isFIFO!
    is_file = dirent.isFile!
    is_socket = dirent.isSocket!
    is_symbolic_link = dirent.isSymbolicLink!
    full_path = "#{dir}#{path.separator}#{name}"
    dirent = {is_block_device, is_character_device, is_directory, is_fifo, is_file, is_socket, is_symbolic_link}
    return {name, full_path, dirent}
*/

/*
    "name": "files",
    "stats": {
        "atime": "2019-01-28T09:54:45.627Z",
        "atimeMs": 1548669285626.642,
        "birthtime": "2017-01-31T12:11:35.000Z",
        "birthtimeMs": 1485864695000,
        "blksize": 4096,
        "blocks": 0,
        "ctime": "2018-03-22T14:06:10.410Z",
        "ctimeMs": 1521727570409.7114,
        "dev": 16777220,
        "gid": 20,
        "ino": 4297557951,
        "mode": 16877,
        "mtime": "2018-03-22T14:06:10.410Z",
        "mtimeMs": 1521727570409.7114,
        "nlink": 4,
        "rdev": 0,
        "size": 128,
        "uid": 501
    }
*/
const COMPACT_FIELD_LIST = <[
    gid
    mode
    mtimeMs
    size
    uid
  ]>

REFORMAT_STATS = (stats) ->
  xs = [ [c, stats[c]] for c in COMPACT_FIELD_LIST ]
  xs = { [x[0], x[1]] for x in xs when x[1]? }
  return xs


class StatFile
  (@dir, @name) ->
    return

  stat: (done) ->
    {dir, name} = self = @
    self.full_path = p = "#{dir}#{path.sep}#{name}"
    self.stats = null
    (err, stats) <- fs.stat p
    self.stats = stats
    is_block_device = stats.isBlockDevice!
    is_character_device = stats.isCharacterDevice!
    is_directory = stats.isDirectory!
    is_fifo = stats.isFIFO!
    is_file = stats.isFile!
    is_socket = stats.isSocket!
    is_symbolic_link = stats.isSymbolicLink!
    xs = [ is_block_device, is_character_device, is_directory, is_fifo, is_file, is_socket, is_symbolic_link ]
    xs = [ (if x then \1 else \0) for x in xs ]
    xs = xs.join ''
    self.dirent = xs
    return done err

  to-json: (format=\full) ->
    {name, stats, dirent} = self = @
    return {name, stats, dirent} if format is \full
    stats = REFORMAT_STATS stats
    return {name, stats, dirent}


class DownloadFileTask
  (@parent, @uri, @username, @password, @dir, @retry, @sha256=null) ->
    @codes = []
    @prefix = parent.prefix
    return

  start-internally: ->
    {parent, command, cwd} = self = @
    self.progress-events = []
    self.stdout-reader.removeAllListeners \data if self.stdout-reader?
    self.stderr-reader.removeAllListeners \data if self.stderr-reader?
    shell = yes
    options = {cwd, shell}
    child = self.child = spawn command, [], options
    self.stdout-reader = byline child.stdout
    self.stderr-reader = byline child.stderr
    self.stdout-reader.on \data, (line) -> return self.at-line \stdout, line.toString!
    self.stderr-reader.on \data, (line) -> return self.at-line \stderr, line.toString!
    child.on \exit, (code, signal) -> return self.at-exit code, signal

  process-progress: (progress, speed, seconds, end=no) ->
    progress = progress.substring 0, progress.length - 1
    progress = parseInt progress
    seconds = seconds.substring 0, seconds.length - 1
    seconds = parseFloat seconds
    evt = {progress, speed, seconds}
    @.progress-events.push evt if progress < 100  # don't send `100` progress to cloud!!

  process-downloaded: (line) ->
    {prefix} = self = @
    tokens = line.split "'"
    self.filename = filename = tokens[1]
    INFO "#{prefix}: filename => #{filename.yellow}"

  verify-checksum: ->
    {prefix, filepath, sha256, done} = self = @
    return done null, {filepath: filepath, checksum: no} unless sha256? and \string is typeof sha256
    self.total-bytes = 0
    hash = crypto.createHash \sha256
    input = fs.createReadStream "#{filepath}"
    input.on \readable, ->
      data = input.read!
      self.total-bytes = self.total-bytes + data.length if data?
      INFO "#{prefix}: verifying integrality: #{self.total-bytes} bytes"
      return hash.update data if data?
      checksum = hash.digest \hex
      INFO "#{prefix}: #{checksum.yellow} v.s. #{sha256.cyan}"
      return done null, {filepath: filepath, checksum: yes} if checksum is sha256
      return done {name: \FILEMGR_ERR_AGENT_MISMATCH_CHECKSUM, message: "checksum verification failure, expects #{sha256} but #{checksum}"}

  at-line: (std, line) ->
    {prefix} = self = @
    tokens = line.split ' '
    output = if std is \stdout then line.gray else line.red
    INFO "#{prefix}: #{std} => #{output}"
    return unless std is \stderr
    return self.process-downloaded line if -1 isnt line.indexOf "saved"
    [k, ...middle, percentage, speed, seconds] = tokens
    return self.process-progress percentage, speed, seconds if percentage.endsWith "%"
    [k, ...middle, percentage, speed] = tokens
    [speed, seconds] = speed.split '='
    return self.process-progress percentage, speed, seconds, yes if percentage.endsWith "%"

  at-exit: (code, signal) ->
    {done, retry} = self = @
    self.child.removeAllListeners \exit
    self.retry = retry - 1
    self.codes.push code
    return self.verify-checksum! if code is 0
    return self.start-internally! if self.retry > 0
    return done {name: \FILEMGR_ERR_AGENT_RETRY_EXCEEDING, message: "retry exceeded: #{JSON.stringify self.codes}"}

  start: (done) ->
    {parent, prefix, uri, username, password, dir} = self = @
    self.done = done
    auth = if username? and password? then "--user=#{username} --password=#{password}" else ""
    self.filename = path.basename uri
    self.filepath = "#{dir}/#{self.filename}"
    self.cwd = dir
    self.command = command = """
      rm -vf #{self.filepath} && \\
      wget \\
        #{auth} \\
        --continue \\
        --waitretry=1 \\
        --tries=#{self.retry} \\
        --progress=dot \\
        --server-response \\
        --backups=3 \\
        --output-document=#{self.filepath} \\
        #{uri}
      """
    self.retry = 1
    INFO "#{prefix}: command:\n#{command.magenta}"
    return self.start-internally!

  at-check: ->
    {progress-events, parent} = self = @
    evt = progress-events.pop!
    self.progress-events = []
    return unless evt?
    {progress, speed, seconds} = evt
    return parent.feedback-progress PROGRESS_EVENT_INDICATED, progress, [speed, seconds], no


class V1_Task
  (@manager, @workdir, @id, @parameters, @configs, @callback) ->
    @prefix = "#{id}"
    {request_timeout, monitor_timeout} = manager.opts.v1
    @request_timeout = request_timeout
    @monitor_timeout = monitor_timeout
    @timeout = 0
    @running = no
    @logger = null
    @name = "n/a"
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

  process-readdir: ->
    {manager, id, parameters, configs, prefix, workdir, monitor_timeout} = self = @
    return self.feedback-error \FILEMGR_INVALID_REQUEST, "missing parameter for readdir: path" unless parameters.path?
    {field} = parameters
    field = \compact unless field?
    dir = parameters.path
    self.feedback-progress PROGRESS_EVENT_ACKED
    self.timeout = monitor_timeout
    self.running = yes
    self.name = "readdir(#{dir})"
    (stat-err, stats) <- fs.stat dir
    return self.feedback-result {stats: null, error: (SERIALIZE_ERROR stat-err)} if stat-err?
    return self.feedback-result {stats: null, error: "#{dir} is not a directory"} unless stats.isDirectory!
    (readdir-err, dirents) <- fs.readdir dir
    return self.feedback-result {stats: stats, error: (SERIALIZE_ERROR readdir-err)} if readdir-err?
    ds = [ (new StatFile dir, d) for d in dirents ]
    f = (d, cb) -> return d.stat cb
    (err) <- async.each ds, f
    return self.feedback-result {stats: stats, error: (SERIALIZE_ERROR err)} if err?
    dirents = [ (d.to-json field) for d in ds ]
    self.running = no
    return self.feedback-result {stats, dirents}

  process-readFile: ->
    {manager, id, parameters, configs, prefix, workdir, monitor_timeout} = self = @
    return self.feedback-error \FILEMGR_INVALID_REQUEST, "missing parameter for readFile: path" unless parameters.path?
    {format} = parameters
    filepath = parameters.path
    format = \raw unless format?
    self.feedback-progress PROGRESS_EVENT_ACKED
    self.timeout = monitor_timeout
    self.running = yes
    self.name = "readFile(#{filepath})"
    (stat-err, stats) <- fs.stat filepath
    return self.feedback-result {stats: null, error: (SERIALIZE_ERROR stat-err)} if stat-err?
    return self.feedback-result {stats: null, error: (SERIALIZE_ERROR new Error "#{filepath} is not a file")} unless stats.isFile!
    return self.feedback-result {stats: null, error: (SERIALIZE_ERROR new Error "#{filepath} is larger than 10240 bytes: #{stats.size}")} unless stats.size < 10240
    #
    # [todo] `readFile`: implement encoding (reading from parameters), used for text/line/json format when toString()
    #
    (readFile-err, buffer) <- fs.readFile filepath
    return self.feedback-result {stats: stats, error: (SERIALIZE_ERROR readFile-err)} if readFile-err?
    self.running = no
    return self.feedback-result {data: buffer} if format is \raw
    text = buffer.toString!
    return self.feedback-result {data: text} if format is \text
    return self.feedback-result {data: (text.split '\n')} if format is \lines
    try
      json = JSON.parse text
    catch error
      return self.feedback-result {stats: stats, error: (SERIALIZE_ERROR error)}
    return self.feedback-result {data: json}

  process-env: ->
    return @.feedback-result process.env

  process-downloadFile: ->
    {manager, id, parameters, configs, prefix, workdir, monitor_timeout} = self = @
    {uri, username, password, dir} = parameters
    {retry, timeout, sha256} = configs
    return self.feedback-error \FILEMGR_INVALID_REQUEST, "missing parameter for downloadFile: dir" unless dir?
    return self.feedback-error \FILEMGR_INVALID_REQUEST, "missing parameter for downloadFile: uri" unless uri?
    self.inner = inner = new DownloadFileTask self, uri, username, password, dir, retry, sha256
    self.name = "downloadFile(#{uri})"
    self.monitor_timeout = if timeout? and \number is typeof timeout then timeout else monitor_timeout
    self.timeout = self.monitor_timeout
    self.feedback-progress PROGRESS_EVENT_ACKED
    (err) <- mkdirp dir
    return self.feedback-error \FILEMGR_ERR_AGENT_NO_LOGGING_STREAM, "failed to create directory #{dir}", err if err?
    INFO "#{prefix}: #{dir} is created successfully, then start downloading with timeout(#{self.timeout}s) and retries (#{retry})"
    self.running = yes
    (err, result) <- inner.start
    self.running = no
    return self.feedback-error err.name, err.message if err?
    return self.feedback-result result

  start: ->
    {manager, id, parameters, configs, prefix, workdir, monitor_timeout} = self = @
    return self.feedback-error \FILEMGR_INVALID_REQUEST, "missing parameters!!" unless parameters?
    INFO "#{prefix}: requesting => parameters: #{(JSON.stringify parameters).gray}"
    INFO "#{prefix}: requesting => configs: #{(JSON.stringify configs).gray}"
    {operation} = parameters
    return self.feedback-error \FILEMGR_INVALID_REQUEST, "missing parameter: operation" unless operation?
    name = "process-#{operation}"
    func = self[(lodash_camelCase name)]
    return self.feedback-error \FILEMGR_INVALID_REQUEST, "unsupported operation: #{operation}" unless func? and \function is typeof func
    return func.apply self, []

  at-check: ->
    {prefix, running, inner, timeout, monitor_timeout, name} = self = @
    return unless running
    return WARN "#{prefix} timeout value is unexpected: #{timeout}" unless timeout > 0
    self.timeout = timeout - 1
    if self.timeout > 0
      DBG "#{prefix}: waiting for `#{name.cyan}` (#{self.timeout} seconds ...)"
      return inner.at-check!
    else
      INFO "#{prefix}: timeout!!"
      self.feedback-error \FILEMGR_ERR_AGENT_TIMEOUT, "#{name} request takes more than #{monitor_timeout}s"
      self.running = no
      return inner.stop!
    /*
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
    # self.write-log \timeout, {monitor_timeout}, yes




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
    [reg-err, handler] = ttysock.addChannelHandler AGENT_EVENT_FILE_MANAGER, __filename, self
    return done reg-err if reg-err?
    self.handler = handler
    self.timer = setInterval f, 1000ms
    return done!

  feedback: (tid, progress, result, error, lossless=yes) ->
    {handler} = self = @
    INFO "feedback: AGENT_EVENT_FILE_MANAGER/#{tid} => progress: #{JSON.stringify progress}"
    INFO "feedback: AGENT_EVENT_FILE_MANAGER/#{tid} => result: #{JSON.stringify result}"
    INFO "feedback: AGENT_EVENT_FILE_MANAGER/#{tid} => error: #{JSON.stringify error}"
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

  upload-archive: (prefix, tid, filepath, callback) ->
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
    qs = {task, target}
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

  process_ttys_event: (evt, request-version, request-id, parameters, configs, callback) ->
    {workdir, tasks} = self = @
    return self.feedback-error request-id, FILEMGR_INVALID_REQUEST, "unsupported request: #{request-version}" unless request-version is \v1
    parameters = MERGE_TEMPLATE parameters
    t = tasks[request-id] = new V1_Task self, workdir, request-id, parameters, configs, callback
    t.start!



module.exports = exports =
  attach: (opts, helpers) ->
    app = @
    module.helpers = helpers
    module.manager = app.agent-filemgr-service = new ServiceManager opts, app

  init: (done) ->
    {manager} = module
    {system-info, ps, tty} = app = @
    return done new Error "#{NAME} depends on plugin #{'system-info'.yellow} but missing" unless system-info?
    return done new Error "#{NAME} depends on plugin #{'ps'.yellow} but missing" unless ps?
    return done new Error "#{NAME} depends on plugin #{'tty'.yellow} but missing" unless tty?
    return manager.init system-info, ps, tty, done
