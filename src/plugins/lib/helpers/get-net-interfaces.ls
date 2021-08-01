#!/usr/bin/env lsc
#
# Copyright (c) 2018 T2T Inc. All rights reserved
# https://www.t2t.io
# https://tic-tac-toe.io
# Taipei, Taiwan
#
require! <[fs path]>
si = require \systeminformation


##
# https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/networking_guide/ch-consistent_network_device_naming
#
# Scheme 1:
#     Names incorporating Firmware or BIOS provided index numbers for on-board
#     devices (example: `eno1`), are applied if that information from the firmware
#     or BIOS is applicable and available, else falling back to scheme 2.
#
# Scheme 2:
#     Names incorporating Firmware or BIOS provided PCI Express hotplug slot index
#     numbers (example: `ens1`) are applied if that information from the firmware
#     or BIOS is applicable and available, else falling back to scheme 3.
#
# Scheme 3:
#     Names incorporating physical location of the connector of the hardware
#     (example: `enp2s0`), are applied if applicable, else falling directly
#     back to scheme 5 in all other cases.
#
# Scheme 4:
#     Names incorporating interface's MAC address (example: enx78e7d1ea46da),
#     is not used by default, but is available if the user chooses.
#
# Scheme 5:
#     The traditional unpredictable kernel naming scheme, is used if all
#     other methods fail (example: eth0).
#

const REGEXP_ENP  = /^enp[0-9]+s[0-9]+$/
const REGEXP_ENX  = /^enx[0-9a-f]*/
const REGEXP_EN   = /^en[0-9][0-9]*$/
const REGEXP_ETH  = /^eth[0-9][0-9]*$/
const REGEXP_WLAN = /^wlan[0-9][0-9]*$/
const REGEXP_PPP  = /^ppp[0-9][0-9]*$/
const REGEXP_USB  = /^usb[0-9][0-9]*$/

const REGEXP_FOR_INTERFACES = [
  REGEXP_ENP,
  REGEXP_ENX,
  REGEXP_EN,
  REGEXP_ETH,
  REGEXP_WLAN,
  REGEXP_PPP,
  REGEXP_USB
]


APPLY_NAME_TEST = (regexp, ifs) ->
  return [ i for i in ifs when regexp.test i.iface ]



GET_NET_INTERFACES = (done) ->
  interfaces = []
  name = \enx112233445566
  mac = \11:22:33:44:55:66
  ipv4 = \0.0.0.0
  mac_address = mac.split ":" .join ""
  iface = {name: name, iface: {ipv4, mac}}
  results = {mac_address, iface, interfaces}
  return done null, results if process.env['TOE_APP_SYSTEM_INFO_FORCE_DUMMY_NETIF'] is \true
  ###
  # $ systeminformation.networkInterfaces(cb)
  #
  # [{
  #   "iface": "en15",
  #   "ifaceName": "en15",
  #   "ip4": "10.42.0.50",
  #   "ip6": "fe80::46e:c8c9:2a9:3a07",
  #   "mac": "00:e0:4c:68:d3:82",
  #   "internal": false,
  #   "virtual": false,
  #   "operstate": "up",
  #   "type": "wired",
  #   "duplex": "full",
  #   "mtu": 1500,
  #   "speed": 1000,
  #   "carrierChanges": 0}
  # ]
  #
  (interfaces) <- si.networkInterfaces
  xs = [ d for d in interfaces ]
  console.log "\txs => #{JSON.stringify xs}"
  xs = [ x for x in xs when x.speed isnt -1 ]
  console.log "\txs => #{JSON.stringify xs}"
  ys = [ (APPLY_NAME_TEST r, xs) for r in REGEXP_FOR_INTERFACES ]
  console.log "\tys => #{JSON.stringify ys}"
  ys = [ y for y in ys when y.length isnt 0 ]
  console.log "\tys => #{JSON.stringify ys}"
  d = ys.shift!
  console.log "\td => #{JSON.stringify d}"
  return done null, results unless d? and Array.isArray d and d.length > 0
  if d.length > 1
    zs = [ z for z in d when z.ip4 != "" ]
    console.log "\tzs => #{JSON.stringify zs}"
    d = if zs.length > 0 then zs[0] else d[0]       # when the `ip4` field of all interfaces are blank string, then select at least one interface.
  else
    d = d[0]
  console.log "\td.final => #{JSON.stringify d}"
  name = \enx112233445566
  name = d.iface if d?.iface?
  mac = \11:22:33:44:55:66
  mac = d.mac if d?.mac?
  ipv4 = \0.0.0.0
  ipv4 = d.ip4 if d?.ip4?
  mac_address = mac.split ":" .join ""
  iface = {name: name, iface: {ipv4, mac}}
  results = {mac_address, iface, interfaces}
  return done null, results



##
#
# Output: `mac_address`, `iface`, `interfaces`.
#
module.exports = exports = GET_NET_INTERFACES


return unless __filename is process.argv[1] or __filename.startsWith process.argv[2]
##
# -- main --
#
start = new Date!
(err, ifs) <- GET_NET_INTERFACES
console.log "err => #{err}"
console.log "ifs => #{JSON.stringify ifs, null, ' '}"
duration = (new Date!) - start
console.log "duration: #{duration}ms"
