import flatten from require "pgmoon.util"

posix_socket = require "posix.sys.socket"
posix_unistd = require "posix.unistd"
posix_errno = require "posix.errno"
posix_poll = require "posix.poll"

strerror = (code) ->
  if code
    posix_errno.strerror code
  else
    posix_errno.strerror posix_errno.errno!

should_retry = (code) ->
  code == posix_errno.EINTR or code == posix_errno.EAGAIN or code == posix_errno.EWOULDBLOCK

poll_events = {
  read: posix_poll.POLLIN
  write: posix_poll.POLLOUT
}

socket_path_for = (host, port) ->
  assert host and host != "", "luaposix socket requires a host"
  return host unless host\sub(1, 1) == "/"

  if host\match ".s%.PGSQL%.%d+$"
    host
  else
    port = tostring(port or "5432")
    prefix = if host\sub(-1) == "/" then host\sub(1, -2) else host
    "#{prefix}/.s.PGSQL.#{port}"

class PosixSocket
  new: =>
    @fd = nil
    @timeout = nil

  connect: (host, port) =>
    path = socket_path_for host, port
    return nil, "luaposix socket requires an absolute unix socket path" unless path\sub(1, 1) == "/"

    fd, err, code = posix_socket.socket posix_socket.AF_UNIX, posix_socket.SOCK_STREAM, 0
    unless fd
      return nil, err or strerror code

    addr = {
      family: posix_socket.AF_UNIX
      path: path
    }
    ok, connect_err, connect_code = posix_socket.connect fd, addr
    unless ok
      posix_unistd.close fd
      return nil, connect_err or strerror connect_code

    @fd = fd
    true

  wait_for: (what) =>
    return true unless @timeout and @timeout >= 0

    events = poll_events[what]
    assert events, "unknown wait type #{what}"

    fds = {
      {
        fd: @fd
        events: events
      }
    }

    while true
      ready, err, code = posix_poll.poll fds, @timeout
      if ready == 0
        return nil, "timeout"
      if not ready
        if should_retry code
          continue
        return nil, err or strerror code
      return true

  send: (...) =>
    return nil, "socket is not connected" unless @fd

    data = flatten ...
    total = 0
    len = #data

    while total < len
      ok, err = @wait_for "write"
      return nil, err unless ok

      written, write_err, code = posix_unistd.write @fd, data\sub(total + 1)
      unless written
        if should_retry code
          continue
        return nil, write_err or strerror code

      total += written

    total

  receive: (len) =>
    return nil, "socket is not connected" unless @fd
    return nil, "luaposix socket only supports length-based receives" unless type(len) == "number"

    remaining = len
    chunks = {}

    while remaining > 0
      ok, err = @wait_for "read"
      return nil, err unless ok

      chunk, read_err, code = posix_unistd.read @fd, remaining
      unless chunk
        if should_retry code
          continue
        return nil, read_err or strerror code

      if #chunk == 0
        return nil, "closed"

      chunks[#chunks + 1] = chunk
      remaining -= #chunk

    table.concat chunks

  close: =>
    return true unless @fd

    posix_unistd.close @fd
    @fd = nil
    true

  settimeout: (t) =>
    if t == nil
      @timeout = nil
      return

    timeout = assert tonumber(t), "timeout must be numeric"
    if timeout < 0
      @timeout = nil
    else
      @timeout = math.floor timeout

  getreusedtimes: => 0

  setkeepalive: =>
    error "You attempted to call setkeepalive on a luaposix socket. This method is only available for the ngx cosocket API for releasing a socket back into the connection pool"

  sslhandshake: =>
    nil, "luaposix sockets do not support SSL handshakes"

{ :PosixSocket, :socket_path_for }
