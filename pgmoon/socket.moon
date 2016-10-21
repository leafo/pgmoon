
luasocket = do
  import flatten from require "pgmoon.util"

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

  overrides = {
    send: true
    getreusedtimes: true
    sslhandshake: true,
    settimeout: true
  }

  {
    tcp: (...) ->
      socket = require "socket"
      sock = socket.tcp ...
      proxy = setmetatable {
        :sock
        send: (...) => @sock\send flatten ...
        getreusedtimes: => 0
        settimeout: (t) =>
          if t
            t = t/1000
          @sock\settimeout t
        sslhandshake: (_, _, verify, _, opts={}) =>
          ssl = require "ssl"
          params = {
            mode: "client"
            protocol: "tlsv1"
            key: opts.key
            certificate: opts.cert
            cafile: opts.cafile
            verify: verify and "peer" or "none"
            options: "all"
          }

          sec_sock, err = ssl.wrap @sock, params
          return false, err unless sec_sock

          success, err = sec_sock\dohandshake!
          return false, err unless success

          -- purge memoized socket closures
          for k, v in pairs @
            @[k] = nil unless type(v) ~= "function" or overrides[k]

          @sock = sec_sock

          true
      }, proxy_mt

      proxy
  }

{
  new: ->
    -- Fallback to LuaSocket is only required when pgmoon
    -- runs in plain Lua, or in the init_by_lua context.
    if ngx and ngx.get_phase! != "init"
      ngx.socket.tcp!, "nginx"
    else
      luasocket.tcp!, "luasocket"
}

