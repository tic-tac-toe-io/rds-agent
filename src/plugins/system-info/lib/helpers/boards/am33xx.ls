#!/usr/bin/env lsc
#
# Copyright (c) 2018 T2T Inc. All rights reserved
# https://www.t2t.io
# https://tic-tac-toe.io
# Taipei, Taiwan
#
require! <[fs path]>

const EEPROM_PATHES = <[
    /sys/bus/i2c/devices/1-0050/eeprom
    /sys/bus/i2c/devices/0-0050/eeprom
    /sys/bus/i2c/devices/0-0050/at24-0/nvmem
  ]>


GET_EEPROM_PATH = ->
  x = null
  for p in EEPROM_PATHES
    try
      stats = fs.statSync p
      x := p
      # console.log "eeprom => #{p}"
      break
    catch error
      # console.log "checking #{p} but #{error}"
      continue
  return x


DECODE_EEPROM_SIGNATURE = (board, version) ->
  ##
  # EEPROM Signatures from https://github.com/beagleboard/image-builder
  #   - BeagleBoard.org BeagleBone (original bone/white)
  #   - BeagleBoard.org or Element14 BeagleBone Black
  #   - BeagleBoard.org BeagleBone Blue
  #   - ...
  #
  variant = \BeagleBone
  variant = <[BeagleBoneWhite BeagleBoard.org]> if board is \A335BONE and version in <[00A4 00A5 00A6 0A6A 0A6B 000B]>
  variant = <[BeagleBoneBlack Element14]> if board is \A335BNLT and version in <[00A5 0A5A 0A5B 0A5C 00A6 000C 00C0]>
  variant = <[BeagleBoneBlue BeagleBoard.org]> if board is \A335BNLT and version is \BLA2
  variant = <[BeagleBoneBlackWireless BeagleBoard.org]> if board is \A335BNLT and version is \BWA5
  variant = <[PocketBeagle BeagleBoard.org]> if board is \A335PBGL and version is \00A2
  variant = <[BeagleBoneGreen SeeedStudio]> if board is \A335BNLT and version in <[BBG1 \u001a\u0000\u0000\u0000]>
  variant = <[BeagleBoneGreenWireless SeeedStudio]> if board is \A335BNLT and version is \GW1A
  variant = <[BeagleBoneBlackIndustrial Arrow]> if board is \A335BNLT and version is \AIA0
  variant = <[BeagleBoneBlackIndustrial Element14]> if board is \A335BNLT and version is \EIA0
  variant = ["PocketBone", "Qwerty Embedded Design"] if board is \A335BNLT and version is \BP00
  variant = ["OSD3358-SM-RED", "Octavo Systems"] if board is \A335BNLT and version is \OS00
  variant = ["BeagleBone.A335BNLT.#{version}", "Others"] if variant is \BeagleBone and board is \A335BNLT
  [sku, manufacturer] = variant
  return {sku, manufacturer}


##
#
#
#
module.exports = exports = (system, done) ->
  p = GET_EEPROM_PATH!
  return done "missing eeprom i2c path" unless p? and \string is typeof p
  (open-err, fd) <- fs.open p, 'r'
  return done open-err if open-err?
  # console.log "successfully open #{p} with handle #{fd}"
  b = Buffer.alloc 64, 0
  (read-err, bytes-read, buffer) <- fs.read fd, b, 0, 64, 0
  fs.close fd, (err) -> console.error "failed to close fd #{fd} for reading 64 bytes from #{p}, err => #{err}" if err?
  return done read-err if read-err?
  return done "expects 64 bytes but only #{bytes-read} bytes" unless bytes-read is 64
  # console.log "data: #{b.toString 'hex'}"
  header = (Buffer.from b[0 to 3]).toString 'hex'
  return done "expects aa5533ee header but #{header}" unless header is \aa5533ee
  # console.log "header: #{header}"
  board = (Buffer.from b[4 to 11]).toString!
  version = (Buffer.from b[12 to 15]).toString!
  serial = (Buffer.from b[16 to 27]).toString!
  {sku, manufacturer} = DECODE_EEPROM_SIGNATURE board, version
  system <<< {version, serial, manufacturer, sku}
  return done null, system
