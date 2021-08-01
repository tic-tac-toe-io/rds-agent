require! <[fs path]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{mkdirp} = global.get-bundled-modules!

const KEY = "PROFILE_STORAGE_DIR"

class Manager
  (@opts, @helpers) ->
    {app-name} = opts
    profile-dir = @profile-dir = if process.env[KEY]? then process.env[KEY] else "/tmp"
    app-dir = @app-dir = "#{profile-dir}#{path.sep}#{app-name}"
    INFO "profile-dir: #{@profile-dir.green}"
    INFO "app-dir: #{@app-dir.green}"
    return

  init: (done) ->
    {profile-dir, app-dir, opts} = @
    (err-p) <- mkdirp profile-dir
    return done err-p if err-p?
    (err-a) <- mkdirp app-dir
    return done err-a

  get-profile-dir: (name) ->
    {profile-dir} = @
    return "#{profile-dir}#{path.sep}#{name}"

  get-app-dir: (name) ->
    {app-dir} = @
    return "#{app-dir}#{path.sep}#{name}"



module.exports = exports =

  attach: (opts, helpers) ->
    module.opts = opts
    module.helpers = helpers
    @ps = module.ps = new Manager opts, helpers
    return

  init: (done) ->
    app = @
    {ps} = module
    return ps.init done
