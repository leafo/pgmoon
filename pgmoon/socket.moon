
if ngx
  return { tcp: ngx.socket.tcp }

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

socket = require "socket"

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
    sock = socket.tcp ...
    proxy = setmetatable {
      :sock
      send: (...) => @sock\send _flatten ...
      getreusedtimes: => 0
    }, proxy_mt

    proxy
}

