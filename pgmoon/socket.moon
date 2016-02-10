
luasocket = do
  -- make luasockets send behave like openresty's
  __flatten = (t, buffer) ->
    switch type(t)
      when "string"
        buffer[#buffer + 1] = t
      when "table"
        for thing in *t
          __flatten thing, buffer


  _flatten = (t) ->
    buffer = {}
    __flatten t, buffer
    table.concat buffer

  proxy_mt = {
    __index: (key) =>
      sock = @sock
      original = sock[key]
      if type(original) == "function"
        fn = (_, ...) ->
          original sock, ...
        @[key] = fn
        fn
      else
        original
  }

  {
    tcp: (...) ->
      socket = require "socket"
      sock = socket.tcp ...
      proxy = setmetatable {
        :sock
        send: (...) => @sock\send _flatten ...
        getreusedtimes: => 0
      }, proxy_mt

      proxy
  }

{
  new: ->
    -- Fallback to LuaSocket is only required when pgmoon
    -- runs in plain Lua, or in the init_by_lua context.
    if ngx and ngx.get_phase! != "init"
      ngx.socket.tcp!
    else
      luasocket.tcp!
}

