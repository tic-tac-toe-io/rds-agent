const AGENT_EVENT_COMMAND = \command
const AGENT_EVENT_REGISTER = \register
const AGENT_EVENT_REGISTER_ACKED = \register-acked    # since 0.2.0
const AGENT_EVENT_HTTP_BY_SERVER = \http-by-server    # since 0.2.0
const AGENT_EVENT_HTTP_BY_AGENT = \http-by-agent      # since 0.2.0
const AGENT_EVENT_BASH_BY_SERVER = \bash-by-server    # since 0.3.0
const AGENT_EVENT_FILE_MANAGER = \filemgr             # since 0.4.0

const PROGRESS_EVENT_ACKED = \acked
const PROGRESS_EVENT_INDICATED = \indicated

const HTTP_INVALID_REQUEST = 1
const HTTP_REQUEST_ERROR = 2
const HTTP_INTERRUPT_ERROR = 3

const FILEMGR_INVALID_REQUEST = 31
const FILEMGR_INTERRUPT_ERROR = 33

##
# The http request is initiated by WsttyServer, Agent executes the request
# and timeout at Agent side. Agent has 2 timeouts:
#
# 1. The timeout as option to `request` library
# 2. The timeout to monitor the entire http request operation
#
# `1` shall be configured to 60s, while `2` shall be configured to 120s
# because of this:
#
#   the default in Linux can be anywhere from 20-120 seconds.
#   http://www.sekuda.com/overriding_the_default_linux_kernel_20_second_tcp_socket_connect_timeout
#
const HTTP_BY_AGENT_ERR_AGENT_TIMEOUT = 10

##
# The http request is initiated by WsttyServer, Agent executes the request
# and timeout at Server side. The timeout is configured as 1.5 times of the timeout
# of Agent side: 120 * 1.5 = 180s.
#
# And, it's recommended to configure reverse-proxy (e.g. Nginx) for WsttyServer
# to have timeout as `twice` of the timeout at Agent side: 120 * 2 = 240s
#
#   location / {
#       proxy_read_timeout      240;    <=== Please configure this!!
#       proxy_connect_timeout   60;
#       proxy_redirect          off;
#       ...
#   }
#
const HTTP_BY_AGENT_ERR_SERVER_TIMEOUT = 11

const HTTP_BY_SERVER_ERR_AGENT_TIMEOUT = 12
const HTTP_BY_SERVER_ERR_SERVER_TIMEOUT = 13


const BASH_BY_SERVER_ERR_AGENT_TIMEOUT = 21
const BASH_BY_SERVER_ERR_SERVER_TIMEOUT = 22
const BASH_BY_SERVER_ERR_AGENT_NO_LOGGING_STREAM = 23

const FILEMGR_ERR_AGENT_TIMEOUT = 31
const FILEMGR_ERR_AGENT_NO_LOGGING_STREAM = 33
const FILEMGR_ERR_AGENT_MISMATCH_CHECKSUM = 34
const FILEMGR_ERR_AGENT_RETRY_EXCEEDING = 35

module.exports = exports =
  events: {
    AGENT_EVENT_COMMAND, AGENT_EVENT_REGISTER,
    AGENT_EVENT_REGISTER_ACKED,
    AGENT_EVENT_HTTP_BY_SERVER, AGENT_EVENT_HTTP_BY_AGENT,
    AGENT_EVENT_BASH_BY_SERVER,
    AGENT_EVENT_FILE_MANAGER
  }
  constants: {
    HTTP_INVALID_REQUEST,
    HTTP_REQUEST_ERROR,
    HTTP_BY_AGENT_ERR_AGENT_TIMEOUT,
    HTTP_BY_AGENT_ERR_SERVER_TIMEOUT,
    HTTP_BY_SERVER_ERR_AGENT_TIMEOUT,
    HTTP_BY_SERVER_ERR_SERVER_TIMEOUT,

    BASH_BY_SERVER_ERR_AGENT_TIMEOUT,
    BASH_BY_SERVER_ERR_SERVER_TIMEOUT,
    BASH_BY_SERVER_ERR_AGENT_NO_LOGGING_STREAM,

    FILEMGR_INVALID_REQUEST,
    FILEMGR_INTERRUPT_ERROR,
    FILEMGR_ERR_AGENT_TIMEOUT,
    FILEMGR_ERR_AGENT_NO_LOGGING_STREAM,
    FILEMGR_ERR_AGENT_MISMATCH_CHECKSUM,
    FILEMGR_ERR_AGENT_RETRY_EXCEEDING,

    PROGRESS_EVENT_ACKED,
    PROGRESS_EVENT_INDICATED
  }
