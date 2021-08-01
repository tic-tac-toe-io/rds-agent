require! <[moment]>
{DBG, INFO, WARN, ERR} = global.get-logger __filename


class Helper
  (@name, @opts, @app) ->
    {date, time} = opts
    @date-format = date
    @date-format = \MMM/DD unless @date-format
    @time-format = time
    @time-format = \HH:mm:ss:SSS unless @time-format?
    return


  init: (done) ->
    {app} = self = @
    app.on \dump-info-service, -> self.at-dump-info.apply self, arguments
    return done!


  at-dump-info: (name, tokens) ->
    {app, date-format, time-format} = self = @
    {sock} = app
    now = moment!
    date = now.format date-format
    time = now.format time-format
    xs = [date.gray, time] ++ tokens
    return sock.send-line name, (xs.join "\t")


module.exports = exports = Helper