{DBG, ERR, WARN, INFO} = global.get-logger __filename
{EventEmitter} = require \events
require! <[moment]>

class Terminal
  (@opts) ->
    @.ee = new EventEmitter!

  on: (event, listener) -> return @.ee.on event, listener
  removeAllListeners: (event) -> return @.ee.removeAllListeners event
  write: (chunk) -> return
  destroy: -> return
  control: (params) -> return



class PTY extends Terminal
  (@opts) ->
    super ...
    {spawn} = require \node-pty
    self = @
    opts = {} unless opts?
    opts.cols = 80 unless opts.cols?
    opts.rows = 25 unless opts.rows?
    opts.name = \xterm-color
    opts.env = process.env
    opts.cwd = process.env.HOME unless opts.cwd?
    term = @term = spawn '/bin/bash', [], opts
    term.on \exit, (code, signal) -> return self.ee.emit \exit, code, signal
    term.on \data, (chunk) -> return self.ee.emit \data, chunk

  write: (chunk) ->
    super ...
    return @term.write chunk

  destroy: ->
    return @term.destroy!



class FORK extends Terminal
  (@opts) ->
    super ...
    require! <[byline]>
    self = @
    {spawn} = require \child_process
    {command, args, options} = opts
    # INFO "opts: #{JSON.stringify opts}"
    args = [] unless args?
    options = {} unless options?
    options.cwd = process.env.HOME unless options.cwd
    options.env = process.env
    # INFO "spawn: #{command}"
    # INFO "spawn: #{JSON.stringify args}"
    child = @child = spawn command, args, options
    child.on \exit, (code, signal) -> self.at-exit code, signal
    out-line-stream = @bout = byline child.stdout
    err-line-stream = @berr = byline child.stderr
    out-line-stream.on \data, (line) -> self.at-line \stdout, line
    err-line-stream.on \data, (line) -> self.at-line \stderr, line
    out-line-stream.on \end, -> self.at-close \stdout
    err-line-stream.on \end, -> self.at-close \stderr

    child.stdout.on \end, -> self.show-stream-event \stdout, \end
    child.stderr.on \end, -> self.show-stream-event \stderr, \end
    child.stdout.on \close, -> self.show-stream-event \stdout, \close
    child.stderr.on \close, -> self.show-stream-event \stderr, \close
    child.stdout.on \err, (err) -> self.show-stream-event \stdout, \err, "error", err
    child.stderr.on \err, (err) -> self.show-stream-event \stderr, \err, "error", err

    out-line-stream.on \end, -> self.show-stream-event \stdout-byline, \end
    err-line-stream.on \end, -> self.show-stream-event \stderr-byline, \end
    out-line-stream.on \close, -> self.show-stream-event \stdout-byline, \close
    err-line-stream.on \close, -> self.show-stream-event \stderr-byline, \close
    out-line-stream.on \err, (err) -> self.show-stream-event \stdout-byline, \err, "error", err
    err-line-stream.on \err, (err) -> self.show-stream-event \stderr-byline, \err, "error", err

    @stdout-closed = no
    @stderr-closed = no
    @exit-pending = no
    @exit-status = {}
    @packets = []
    f = -> return self.at-timeout!
    @timeout = setInterval f, 2000ms


  show-stream-event: (name, evt, message=null, err=null) ->
    {packets} = self = @
    output = "#{name}.#{evt}"
    output = "#{output} => #{message}" if message?
    now = moment!
    now = now.format 'MM/DD HH:mm:ss:SSS'
    exx = null
    exx = "#{err}" if err?
    packets.push {std: \sys, name: name, evt: evt, message: message, error: exx, time: now}
    return INFO output unless err?
    return WARN err, output


  flush: ->
    {packets, ee} = self = @
    @packets = []
    return ee.emit \data, (JSON.stringify packets)


  cleanup: ->
    {child, bout, berr, timeout} = self = @
    child.removeAllListeners \exit
    bout.removeAllListeners \data
    bout.removeAllListeners \end
    berr.removeAllListeners \data
    berr.removeAllListeners \end
    clearInterval timeout
    return


  at-timeout: ->
    return @.flush!


  at-close: (std) ->
    {exit-pending, exit-status} = self = @
    {code, signal} = exit-status
    @stdout-closed = yes if std is \stdout
    @stderr-closed = yes if std is \stderr
    return unless self.stdout-closed and self.stderr-closed and exit-pending
    self.flush!
    self.cleanup!
    INFO "exit: #{code}, #{signal} (after stdout/stderr are closed)"
    return self.ee.emit \exit, code, signal


  at-line: (std, chunk) ->
    {packets} = @
    INFO "#{std}: #{chunk}"
    return packets.push {std: std, line: "#{chunk}"}


  at-exit: (code, signal) ->
    {stdout-closed, stderr-closed, ee} = self = @
    if stdout-closed and stderr-closed
      INFO "exit: #{code}, #{signal}"
      self.flush!
      return ee.emit \exit, code, signal
    else
      INFO "exit: #{code}, #{signal}, pending"
      self.exit-status = code: code, signal: signal
      self.exit-pending = yes


  write: (chunk) ->
    # INFO "stdin: #{chunk}"
    return @child.stdin.write chunk


  control: (params) ->
    {type} = params
    return @.child.stdin.end! if type is \close-input
    return WARN "unsupported control: #{JSON.stringify params}"

  destroy: ->
    return @child.kill \SIGHUP



module.exports = exports =
  create-tty: (params) ->
    {type, options} = params
    return new PTY options if type is \pty
    return new FORK options if type is \fork
    return null
