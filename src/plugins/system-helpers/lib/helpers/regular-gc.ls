require! <[path]>
{DBG, INFO, WARN, ERR} = global.get-logger __filename


class Helper
  (@name, @opts, @app) ->
    @period = opts.period
    @period = 60s unless @period?
    @counter = 0
    return

  init: (done) ->
    {period} = self = @
    INFO "period = #{period}"
    f = -> return self.timeout.apply self, []
    setInterval f, 1000ms
    return done!


  run: ->
    return WARN "missing global.gc() function" unless global.gc?
    global.gc!
    return INFO "run global.gc()"


  timeout: ->
    @.run! if @counter == 0
    @counter = @counter + 1
    @counter = 0 if @counter >= @period
    return


module.exports = exports = Helper
