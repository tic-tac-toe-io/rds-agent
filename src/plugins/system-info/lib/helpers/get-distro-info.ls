#
# Copyright (c) 2018 T2T Inc. All rights reserved
# https://www.t2t.io
# https://tic-tac-toe.io
# Taipei, Taiwan
#
require! <[fs path]>
{exec} = require \child_process


EXEC_WITH_FALLBACK = (command, fallback, single, lower, done) ->
  (err, stdout, stderr) <- exec command
  if err?
    console.log "failed to execute #{command} => #{err}"
    return done fallback
  else
    text = stdout.toString!
    text = text.toLowerCase! if lower
    return done text unless single
    xs = text.split '\n'
    return done xs[0]


GET_DARWIN_NAME = (uname, done) ->
  (codename) <- EXEC_WITH_FALLBACK "sw_vers -productVersion", "unknown", yes, yes
  name = "macosx"
  dist = {name, codename}
  name = "#{uname.kernel}-#{name}"
  arch = uname.architecture
  return done null, {name, arch, uname, dist}


GET_LINUX_NAME = (uname, done) ->
  (codename) <- EXEC_WITH_FALLBACK "lsb_release -a 2>/dev/null | grep '^Codename' | awk '{print $2}'", "unknown", yes, yes
  (name) <- EXEC_WITH_FALLBACK "lsb_release -a 2>/dev/null | grep '^Distributor' | awk '{print $3}'", "unknown", yes, yes
  dist = {name, codename}
  name = "#{uname.kernel}-#{name}-#{codename}"
  arch = uname.architecture
  return done null, {name, arch, uname, dist}


##
#
# Implement this logic: https://github.com/yagamy4680/bash-utils/blob/master/system#L66-L74
#
GET_SYSTEM_NAME = (done) ->
  (kernel) <- EXEC_WITH_FALLBACK "uname -s", "unknown", yes, yes
  (architecture) <- EXEC_WITH_FALLBACK "uname -m", "unknown", yes, yes
  (release) <- EXEC_WITH_FALLBACK "uname -r", "unknown", yes, yes
  uname = {kernel, architecture, release}
  return GET_DARWIN_NAME uname, done if kernel is \darwin
  return GET_LINUX_NAME uname, done if kernel is \linux
  return done null, {uname}


GET_SYSTEM_NAME_WITH_NODE = (done) ->
  (err, data) <- GET_SYSTEM_NAME
  return done err if err?
  {arch, platform} = process
  node = {arch, platform}
  data <<< {node}
  return done null, data


module.exports = exports = GET_SYSTEM_NAME

# console.log "process.argv => #{JSON.stringify process.argv}"
# console.log "__filename => #{__filename}"
return unless __filename is process.argv[1] or __filename.startsWith process.argv[2]
##
# -- main --
#
start = new Date!
(err, names) <- GET_SYSTEM_NAME_WITH_NODE
console.log "err => #{err}"
console.log "names => #{JSON.stringify names}"
duration = (new Date!) - start
console.log "duration: #{duration}ms"