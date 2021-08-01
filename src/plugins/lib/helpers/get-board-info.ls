#!/usr/bin/env lsc
#
# Copyright (c) 2018 T2T Inc. All rights reserved
# https://www.t2t.io
# https://tic-tac-toe.io
# Taipei, Taiwan
#
require! <[fs path]>
si = require \systeminformation


GET_BOARD_INFO = (system, done) ->
  return ((require \./boards/am33xx) system, done) if /\ am33xx\ /i .test system.model
  return done null, system

##
#
module.exports = exports = GET_BOARD_INFO


return unless __filename is process.argv[1] or __filename.startsWith process.argv[2]
##
# -- main --
#
start = new Date!
(system) <- si.system
(err, board) <- GET_BOARD_INFO system
console.log "err => #{err}"
console.log "board => #{JSON.stringify board, null, ' '}"
duration = (new Date!) - start
console.log "duration: #{duration}ms"
