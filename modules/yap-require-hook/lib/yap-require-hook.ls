#
# yap-require-hook
#
module.initialized = no
module.loaded-modules = []

#
# Inspired by
#
# http://fredkschott.com/post/2014/06/require-and-the-module-system/
#

FIND_MODULE = (instance) ->
  {loaded-modules} = module
  ret = null
  for let m, i in loaded-modules
    ret := m if m.module is instance
  return ret


# Hook to `module.js` in nodejs
#
hook = ->
  system = require \module
  {_load} = system
  system._load = (request, parent, isMain) ->
    {pre, post, loaded-modules} = module
    context = pre request, parent, isMain if pre?
    global <<< context if context?
    m = _load request, parent, isMain
    post request, m if post?
    return exports.add-reference m, request



module.exports = exports =

  install: (pre, post) ->
    return if module.initialized
    module.pre = pre if pre?
    module.post = post if post?
    module.initialized = yes
    hook!


  get-name: (m) ->
    require! <[path]>
    mx = FIND_MODULE m
    return null unless mx?
    {name} = mx
    basename = path.basename name
    return {name, basename}


  add-reference: (m, name) ->
    {loaded-modules} = module
    lm = module: m, name: name
    loaded-modules.push lm
    return m
