require! <[colors fs os http systeminformation]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_merge, lodash_find, yapps_utils} = global.get-bundled-modules!
{PRETTIZE_KVS, PRINT_PRETTY_JSON} = yapps_utils.debug
get-distro-info = require \./helpers/get-distro-info
get-board-info = require \./helpers/get-board-info
get-ttt-system = require \./helpers/get-ttt-system
si = require \systeminformation


const LOCALHOST = \127.0.0.1

const TTT_DEFAULTS =
  profile: \misc
  profile_version: \19700101z


GET_IPV4_INFO = (name, faces) ->
  INFO "GET_IPV4_INFO() => name: #{name}, faces: #{JSON.stringify faces}"
  xs = [ f for f in faces when f.family is \IPv4 and f.address? ]
  return null if xs.length is 0
  ys = [ name, xs[0] ]
  return ys


HTTP_REQUEST = (host, port, path, done) ->
  opts = {host, port, path}
  callback = (rsp) ->
    str = ''
    rsp.on \data, (chunk) -> str := str + chunk
    rsp.on \end, -> return done null, str
  req = http.request opts, callback
  req.on \error, (err) -> return done err
  req.end!


MERGE_ENV_VARIABLES = (ttt) ->
  key = \TOE_APP_TTT_ENV_PREFIX
  prefix = process.env[key]
  return ttt unless prefix?
  INFO "found #{key.yellow} => #{prefix.green}"
  xs = [ k for k, v of process.env when k.startsWith "#{prefix}_" ]
  xs = [ [(x.substring prefix.length + 1).to-lower-case!, process.env[x]] for x in xs ]
  xs = { [x[0], x[1]] for x in xs }
  ttt <<< xs
  return ttt


##
# Merge context information from the environment variable `TOE_APP_CONTEXT_EXTRAS` that is
# a set of key value pairs, each pair is separated by `,` while key and value are separated by `:`.
#
# For example, when WsttyAgent is started with these environment variables:
#
# ```text
# TOE_APP_CONTEXT_EXTRAS=rds:1234,token:xyz
# TOE_APP_TTT_ENV_PREFIX=XXX
# XXX_PROFILE=abc
# XXX_PROFILE_VERSION=1234567
# XXX_ID=1234
# XXX_SN=9999
# ```
#
# Then, the `ttt` is updated to :
#
# ```json
# {
#   "profile": "abc",
#   "profile_version": "1234567",
#   "id": "1234",
#   "sn": "9999"
# }
# ```
#
# While, the `context` is added with following json object:
#
# ```json
# {
#   "rds": "1234",
#   "token": "xyx"
# }
# ```
#
MERGE_ENV_CONTEXTS = (ttt) ->
  key = \TOE_APP_CONTEXT_EXTRAS
  vars = process.env[key]
  return ttt unless vars?
  INFO "found #{key.yellow} => #{vars.green}"
  xs = vars.split ','
  xs = [ (x.split ':') for x in xs ]
  xs = { [x[0], x[1]] for x in xs }
  ttt <<< xs
  return ttt


class SystemInfo
  (@opts, @helpers) ->
    self = @
    {remote, ttt_defaults} = opts
    ttt = lodash_merge {}, TTT_DEFAULTS, ttt_defaults
    ttt = MERGE_ENV_VARIABLES ttt
    INFO "ttt => #{PRETTIZE_KVS ttt}"
    self.context = {ttt}
    self.context = MERGE_ENV_CONTEXTS self.context
    INFO "context => #{PRETTIZE_KVS self.context}"
    self.remote = remote
    self.remote = LOCALHOST unless self.remote?
    return

  init: (done) ->
    {remote} = self = @
    (err) <- self.refresh
    return done err if err? and remote isnt LOCALHOST
    WARN err, "failed to update system-info, but ignore it." if err?
    {context} = self
    {mac_address, ttt, os} = context
    {id} = ttt
    {hostname} = os
    {env, pid} = process
    context[\id] = "#{hostname.to-upper-case!}"
    context[\id] = "#{context.id}_112233445566"
    context[\id] = id if id? and id isnt ""
    ttt.id = context.id if ttt.id is ""
    {id} = context
    uptime = (new Date!) - Math.floor process.uptime! * 1000
    uptime = uptime.to-string 16 .to-upper-case!
    pid = process.pid
    context[\instance_id] = "#{id}_#{pid}_#{uptime}"
    INFO "context: #{(JSON.stringify context).green}"
    return done!

  update-ttt-system: (done) ->
    {context, opts} = @
    {ttt_max_read_attempts} = opts
    ttt_max_read_attempts = 3 unless ttt_max_read_attempts?
    start = new Date!
    (err, text) <- get-ttt-system ttt_max_read_attempts
    if err?
      WARN err, "failed to read /tmp/ttt_system"
      return done!
    else
      duration = (new Date!) - start
      try
        xs = text.split '\n'
        xs = [ (x.split '\t') for x in xs when x isnt "" ]
        xs = { [x[0], (if x[1]? then x[1].trim! else x[1])] for x in xs }
        context['ttt'] <<< xs
      catch error
        WARN error, "unexpected error when reading/parsing /tmp/ttt_system"
      return done!

  check-ttt-id: (interfaces) ->
    {context} = self = @
    {ttt, distro} = context
    {kernel, architecture} = distro.uname
    return if ttt.id isnt ""
    xs = [ x for x in interfaces when x.mac isnt '' and x.ip4 isnt '' and x.ip4 isnt '127.0.0.1' and not x.iface.startsWith 'feth' ]
    xs = [ x for x in interfaces when x.mac isnt '' and x.ip4 isnt '' and x.ip4 isnt '127.0.0.1' ] if xs.length is 0
    xs = [ x for x in interfaces when x.mac isnt '' and x.ip4 isnt '' ] if xs.length is 0
    if xs.length is 0
      xs = [ x.iface for x in interfaces ]
      INFO "no network interfaces to be selected to generate identity: #{xs.join ','}"
      mac_address = context['mac_address'] = '11:22:33:44:55:66'
      ipv4 = context['ipv4'] = '0.0.0.0'
    else
      netif = xs[0]
      INFO "the interface #{netif.iface.cyan} is selected to generate identity => #{PRETTIZE_KVS netif}"
      mac_address = context['mac_address'] = netif.mac
      ipv4 = context['ipv4'] = netif.ip4
    mac_address = mac_address.split ':'
    mac_address = mac_address.join ''
    ttt.id = "#{context.os.hostname.toLowerCase!}-#{mac_address}" if kernel is \darwin and architecture is \x86_64
    ttt.id = "#{context.os.hostname.toLowerCase!}-#{mac_address}" if /^raspberry\ /i .test context.system.manufacturer
    ttt.id = "am33xx-#{mac_address}" if /\ am33xx\ /i .test context.system.model
    return

  check-ttt-sn: ->
    {context} = self = @
    {ttt, distro} = context
    {kernel, architecture} = distro.uname
    return unless ttt.sn in ["SANDBOX000000", ""]
    ttt.sn = context.system.serial if context.system.serial isnt ""
    # ttt.sn = system.serial if kernel is \darwin and architecture is \x86_64
    # ttt.sn = system.serial if /^raspberry\ /i .test context.system.manufacturer
    # ttt.sn = system.serial if /\ AM33XX\ /i .test context.system.model
    return

  ##
  # Get these metadata from SensorWeb3 remotely
  #
  refresh-with-remote-data: (host, done) ->
    self = @
    (err, text) <- HTTP_REQUEST host, 6020, '/api/v3/system/metadata'
    return done err if err?
    try
      # INFO "metadata:\n#{text}"
      {data} = JSON.parse text
      self.context = data
      # INFO "context:\n#{JSON.stringify self.context, null, ' '}"
      return done!
    catch error
      return done error

  refresh: (done) ->
    {helpers, context, remote} = self = @
    return self.refresh-with-remote-data remote, done unless remote is LOCALHOST
    node_version = process.version
    node_arch = process.arch
    node_platform = process.platform
    context[\runtime] = {node_version, node_arch, node_platform}
    context[\cwd] = process.cwd!
    (err2, distro) <- get-distro-info   # distro := {name, arch, uname: {kernel, architecture, release}, dist: {name, codename}}
    return done err2 if err2?
    self.context <<< {distro}
    (sys) <- si.system
    (err, results) <- get-board-info sys
    system = if err? then sys else results
    self.context <<< {system}
    (cpu) <- si.cpu
    self.context <<< {cpu}
    (os) <- si.osInfo
    self.context <<< {os}
    {hostname} = self.context.os
    hostname = hostname.substring 0, hostname.length - 6 if hostname.ends-with ".local"
    hostname = hostname.substring 0, hostname.length - 4 if hostname.ends-with ".lan"
    self.context.os.hostname = hostname
    (ttt-err) <- self.update-ttt-system
    return done ttt-err if ttt-err?
    (interfaces) <- systeminformation.networkInterfaces
    context['interfaces'] = interfaces
    self.check-ttt-id interfaces
    self.check-ttt-sn!
    # console.log "context:\n#{JSON.stringify self.context, null, '  '}"
    return done!

  to-json: -> return @context



module.exports = exports =
  attach: (opts, helpers) ->
    module.opts = opts
    module.helpers = helpers
    module.sys = @.system-info = new SystemInfo opts, helpers
    return

  init: (done) ->
    {sys} = module
    return sys.init done
