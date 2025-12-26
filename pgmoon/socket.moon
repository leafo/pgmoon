
-- creates a luaposix unix socket proxy to make it behave like ngx.socket.tcp
create_luaposix_socket = do
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

  -- these methods are overidden from the default socket implementation
  -- all other methods/properties are carried over via the __index metamethod above
  local method_overrides
  method_overrides = {
    connect: (socket_path) =>
      posix_socket = require "posix.sys.socket"
      addr = { family: posix_socket.AF_UNIX, path: socket_path }
      result, err, _ = posix_socket.connect @sock.fd, addr
      if result
        true
      else
        nil, err

    send: (...) =>
      posix_socket = require "posix.sys.socket"
      data = flatten ...
      result, err, _ = posix_socket.send @sock.fd, data
      if result
        #data, nil
      else
        nil, err

    receive: (bytes) =>
      posix_socket = require "posix.sys.socket"
      result, err, _ = posix_socket.recv @sock.fd, bytes
      if result
        result
      else
        nil, err

    settimeout: (t) =>
      -- Unix sockets don't have built-in timeout, but we store it for compatibility
      @timeout = t

    close: =>
      posix_unistd = require "posix.unistd"
      posix_unistd.close @sock.fd

    setkeepalive: =>
      error "You attempted to call setkeepalive on a Unix socket. This method is only available for the ngx cosocket API for releasing a socket back into the connection pool"

    getreusedtimes: (t) => 0

    sslhandshake: (opts={}) =>
      error "SSL handshake is not supported over Unix domain sockets"
  }

  (...) ->
    posix_socket = require "posix.sys.socket"
    sockfd, err, _ = posix_socket.socket posix_socket.AF_UNIX, posix_socket.SOCK_STREAM, 0

    unless sockfd
      error "Failed to create Unix socket: #{err}"

    proxy = {
      sock: { fd: sockfd }
    }

    for k,v in pairs method_overrides
      proxy[k] = v

    setmetatable proxy, proxy_mt

-- creates a luasocket socket proxy to make it behave like ngx.socket.tcp
create_luasocket = do
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

  -- these methods are overidden from the default socket implementation
  -- all other methods/properties are carried over via the __index metamethod above
  local method_overrides
  method_overrides = {
    send: (...) => @sock\send flatten ...

    -- luasocket takes SECONDS while ngx takes MILLISECONDS
    settimeout: (t) =>
      if t
        t = t/1000

      @sock\settimeout t

    setkeepalive: =>
      error "You attempted to call setkeepalive on a LuaSocket socket. This method is only available for the ngx cosocket API for releasing a socket back into the connection pool"

    -- there is no compatible interface here, always return 0 to suggest the
    -- socket is connecting for the first time
    getreusedtimes: (t) => 0

    sslhandshake: (opts={}) =>
      ssl = require "ssl"
      params = {
        mode: "client"
        protocol: "any"
        verify: "none"
        options: { "all", "no_sslv2", "no_sslv3", "no_tlsv1" }
      }

      for k,v in pairs opts
        params[k] = v

      sec_sock, err = ssl.wrap @sock, params
      return false, err unless sec_sock

      success, err = sec_sock\dohandshake!
      return false, err unless success

      -- purge memoized socket closures (created by proxy_mt)
      for k, v in pairs @
        if not method_overrides[k] and type(v) == "function"
          @[k] = nil

      @sock = sec_sock

      true
  }

  (...) ->
    socket = require("socket")
    proxy = {
      sock: socket.tcp ...
    }
    for k,v in pairs method_overrides
      proxy[k] = v

    setmetatable proxy, proxy_mt

{
  :create_luasocket
  :create_luaposix_socket

  new: (socket_type) ->
    if socket_type == nil
      -- TODO: this should not be the responsibility of this library
      -- TODO: write out a warning for some versions, then throw error when socket type is missing
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
        create_luasocket!
      when "luaposix"
        create_luaposix_socket!
      when "cqueues"
        require("pgmoon.cqueues").CqueuesSocket!
      else
        error "got unknown or unset socket type: #{socket_type}"

    socket, socket_type
}

