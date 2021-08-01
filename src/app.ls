#!/usr/bin/env lsc
#
global.yap-context = {module} unless global.yap-context?
yapps = require \./yapps
yapps.init __filename
{DBG, INFO, ERR} = global.get-logger __filename

app = yapps.createApp \base, a: 1, b: 2

app.add-plugin require \./plugins/system-info
app.add-plugin require \./plugins/system-helpers
app.add-plugin require \./plugins/profile-storage
app.add-plugin require \./wstty/services/http-by-server
app.add-plugin require \./wstty/services/bash-by-server
app.add-plugin require \./wstty/services/file-mgr
app.add-plugin require \./wstty/wstty-client

app.init (err) ->
  return ERR err, "failed to initialize app" if err?
  return DBG "started"