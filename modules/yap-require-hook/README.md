# yap-require-hook
A hook to __require__ in nodejs. The hook allows to add context variables before loading a module by `require`.

The hook library offers 2 types of hooks for developers:

- `pre`, before loading a module by `require`
- `post`, after loading a module by `require`

To use the hook library, it's required to call `install` function of the library to wrapper system's module loader. In `install` function, you can specify `pre` and `post` hooks.

The hook library also provides another function `get-name`, that can simply retrieve the name of a loaded nodejs module by given the module's reference.

Here are sample codes:

```livescript
require! <[yap-require-hook]>

pre = (request, parent, isMain) ->
  console.log "pre: #{request}"
  return DBG: (message) -> console.log "aa #{message}"

post = (request, m) ->
  return

yap-require-hook.install pre, post

require! <[async colors]>

console.log "async = #{(yap-require-hook.get-name async) .basename}"
console.log "colors = #{(yap-require-hook.get-name colors) .basename}"
```

The outputs of above sample codes are as follows:

```text
pre: async
pre: colors
pre: ./colors
pre: ./styles
pre: ./system/supports-colors
pre: ./custom/trap
pre: ./custom/zalgo
pre: ./maps/america
pre: ../colors
pre: ./maps/zebra
pre: ../colors
pre: ./maps/rainbow
pre: ../colors
pre: ./maps/random
pre: ../colors
pre: ./extendStringPrototype
pre: ./colors
pre: path
pre: prelude-ls
pre: ./Func.js
pre: ./List.js
pre: ./Obj.js
pre: ./Str.js
pre: ./Num.js
async = async
pre: path
pre: prelude-ls
colors = colors
```

