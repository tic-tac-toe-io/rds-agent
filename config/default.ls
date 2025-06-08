# Definitions
# ======================================================================
#
_definitions:
  TMP: \/tmp
  UNIXSOCK_DIR: \/tmp/yap
  WSTTY:
    production: \https://wstty.tic-tac-toe.io
    development: \http://127.0.0.1:6030
    testing: \http://127.0.0.1:6030



# Metadata
# ======================================================================
#
_metadata:
  transforms:
    integers: []



# Configurations for Plugins
# ======================================================================
#

\system-info :
  verbose: yes
  ttt_max_read_attempts: 3
  ttt_defaults:
    profile: \misc
    profile_version: \19700101a
    id: ''
    sn: \SANDBOX000000
    alias: \UNKNOWN999999

\wstty-client :
  url: '{{use WSTTY}}'
  namespace: 'tty'
  restart_timeout: 20     # 20 minutes
  session_timeout: 2      # 2 minutes
  lookup_next_server: yes

\http-by-server :
  v1:
    request_timeout: 60s
    monitor_timeout: 120s

\bash-by-server :
  v1:
    request_timeout: 61s
    monitor_timeout: 121s



# System-helpers
#
#   `regular-gc`, the garbage collector running in periodic period
#     - period  , the period to run gc(), unit-length is `seconds`.
#
\system-helpers :
  helpers:
    \regular-gc :
      period: 300s
