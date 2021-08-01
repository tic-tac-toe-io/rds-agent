require! <[path colors async]>
{DBG, INFO, WARN, ERR} = global.get-logger __filename


class Manager
  (@app, @opts, @app-helpers) ->
    @helpers = {}
    return

  init: (done) ->
    {app, opts, helpers} = self = @
    for name, o of opts.helpers
      helper = null
      try
        helper-class = switch name
          | \regular-gc => require \./helpers/regular-gc
          | \dump-info-service => require \./helpers/dump-info-service
          | otherwise => null
        helper = new helper-class name, o, app if helper-class?
        helpers[name] := helper if helper?
        INFO "successfully initiate an instance of #{name.green}" if helper?
      catch error
        ERR error, "failed to load helper #{name.yellow}"
        continue

    f = (helper, name, cb) ->
      callbacked = no
      try
        helper.init (err) ->
          callbacked = yes
          return cb err
      catch error
        ERR error, "failed to initiate helper #{name.yellow}"
        return cb error unless callbacked

    return async.for-each-of-series helpers, f, done


  get: (name) ->
    return @helpers[name]




module.exports = exports =
  attach: (opts, helpers) ->
    app = @
    app.system-helpers = module.system-helpers = new Manager app, opts, helpers


  init: (done) ->
    {system-helpers} = app = @
    return system-helpers.init done


