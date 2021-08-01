require! <[serialize-error]>
{handlebars} = global.get-bundled-modules!


SERIALIZE_ERROR = (err) ->
  return err unless err instanceof Error
  xs = serialize-error err
  xs.stack = xs.stack.split '\n'
  return xs


MERGE_TEMPLATE = (opts, context=process.env) ->
  text = JSON.stringify opts
  return opts if -1 is text.indexOf '{{'
  try
    template = handlebars.compile text
    merged = template context
    json = JSON.parse merged
  catch error
    WARN "failed to process template this text: #{text.gray}"
    return opts
  return json


module.exports = exports = {
  SERIALIZE_ERROR
  MERGE_TEMPLATE
}
