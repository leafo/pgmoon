
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
        sslhandshake: (verify, opts={}) =>
          ssl = require "ssl"
          params = {
            mode: "client"
            protocol: opts.ssl_version or "tlsv1"
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
  new: (socket_type) ->
    if socket_type == nil
      -- choose the default socket, try to use nginx, otherwise default to
      -- luasocket
      socket_type = if ngx and ngx.get_phase! != "init"
        "nginx"
      else
        "luasocket"

    socket = switch socket_type
      when "nginx"
        ngx.socket.tcp!
      when "luasocket"
        luasocket.tcp!
      when "cqueues"
        require("pgmoon.cqueues").CqueuesSocket!
      else
        error "unknown socket type: #{socket_type}"

    socket, socket_type
}

