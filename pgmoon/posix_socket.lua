local flatten
flatten = require("pgmoon.util").flatten
local posix_socket = require("posix.sys.socket")
local posix_unistd = require("posix.unistd")
local posix_errno = require("posix.errno")
local posix_poll = require("posix.poll")
local strerror
strerror = function(code)
  if code then
    return posix_errno.strerror(code)
  else
    return posix_errno.strerror(posix_errno.errno())
  end
end
local should_retry
should_retry = function(code)
  return code == posix_errno.EINTR or code == posix_errno.EAGAIN or code == posix_errno.EWOULDBLOCK
end
local poll_events = {
  read = posix_poll.POLLIN,
  write = posix_poll.POLLOUT
}
local socket_path_for
socket_path_for = function(host, port)
  assert(host and host ~= "", "luaposix socket requires a host")
  if not (host:sub(1, 1) == "/") then
    return host
  end
  if host:match(".s%.PGSQL%.%d+$") then
    return host
  else
    port = tostring(port or "5432")
    local prefix
    if host:sub(-1) == "/" then
      prefix = host:sub(1, -2)
    else
      prefix = host
    end
    return tostring(prefix) .. "/.s.PGSQL." .. tostring(port)
  end
end
local PosixSocket
do
  local _class_0
  local _base_0 = {
    connect = function(self, host, port)
      local path = socket_path_for(host, port)
      if not (path:sub(1, 1) == "/") then
        return nil, "luaposix socket requires an absolute unix socket path"
      end
      local fd, err, code = posix_socket.socket(posix_socket.AF_UNIX, posix_socket.SOCK_STREAM, 0)
      if not (fd) then
        return nil, err or strerror(code)
      end
      local addr = {
        family = posix_socket.AF_UNIX,
        path = path
      }
      local ok, connect_err, connect_code = posix_socket.connect(fd, addr)
      if not (ok) then
        posix_unistd.close(fd)
        return nil, connect_err or strerror(connect_code)
      end
      self.fd = fd
      return true
    end,
    wait_for = function(self, what)
      if not (self.timeout and self.timeout >= 0) then
        return true
      end
      local events = poll_events[what]
      assert(events, "unknown wait type " .. tostring(what))
      local fds = {
        {
          fd = self.fd,
          events = events
        }
      }
      while true do
        local _continue_0 = false
        repeat
          do
            local ready, err, code = posix_poll.poll(fds, self.timeout)
            if ready == 0 then
              return nil, "timeout"
            end
            if not ready then
              if should_retry(code) then
                _continue_0 = true
                break
              end
              return nil, err or strerror(code)
            end
            return true
          end
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
    end,
    send = function(self, ...)
      if not (self.fd) then
        return nil, "socket is not connected"
      end
      local data = flatten(...)
      local total = 0
      local len = #data
      while total < len do
        local _continue_0 = false
        repeat
          local ok, err = self:wait_for("write")
          if not (ok) then
            return nil, err
          end
          local written, write_err, code = posix_unistd.write(self.fd, data:sub(total + 1))
          if not (written) then
            if should_retry(code) then
              _continue_0 = true
              break
            end
            return nil, write_err or strerror(code)
          end
          total = total + written
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return total
    end,
    receive = function(self, len)
      if not (self.fd) then
        return nil, "socket is not connected"
      end
      if not (type(len) == "number") then
        return nil, "luaposix socket only supports length-based receives"
      end
      local remaining = len
      local chunks = { }
      while remaining > 0 do
        local _continue_0 = false
        repeat
          local ok, err = self:wait_for("read")
          if not (ok) then
            return nil, err
          end
          local chunk, read_err, code = posix_unistd.read(self.fd, remaining)
          if not (chunk) then
            if should_retry(code) then
              _continue_0 = true
              break
            end
            return nil, read_err or strerror(code)
          end
          if #chunk == 0 then
            return nil, "closed"
          end
          chunks[#chunks + 1] = chunk
          remaining = remaining - #chunk
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return table.concat(chunks)
    end,
    close = function(self)
      if not (self.fd) then
        return true
      end
      posix_unistd.close(self.fd)
      self.fd = nil
      return true
    end,
    settimeout = function(self, t)
      if t == nil then
        self.timeout = nil
        return 
      end
      local timeout = assert(tonumber(t), "timeout must be numeric")
      if timeout < 0 then
        self.timeout = nil
      else
        self.timeout = math.floor(timeout)
      end
    end,
    getreusedtimes = function(self)
      return 0
    end,
    setkeepalive = function(self)
      return error("You attempted to call setkeepalive on a luaposix socket. This method is only available for the ngx cosocket API for releasing a socket back into the connection pool")
    end,
    sslhandshake = function(self)
      return nil, "luaposix sockets do not support SSL handshakes"
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self)
      self.fd = nil
      self.timeout = nil
    end,
    __base = _base_0,
    __name = "PosixSocket"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  PosixSocket = _class_0
end
return {
  PosixSocket = PosixSocket,
  socket_path_for = socket_path_for
}
