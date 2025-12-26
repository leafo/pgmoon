local create_luaposix_socket
do
  local flatten
  flatten = require("pgmoon.util").flatten
  local proxy_mt = {
    __index = function(self, key)
      local sock = self.sock
      local original = sock[key]
      if type(original) == "function" then
        local fn
        fn = function(_, ...)
          return original(sock, ...)
        end
        self[key] = fn
        return fn
      else
        return original
      end
    end
  }
  local method_overrides
  method_overrides = {
    connect = function(self, socket_path)
      local posix_socket = require("posix.sys.socket")
      local addr = {
        family = posix_socket.AF_UNIX,
        path = socket_path
      }
      local result, err, _ = posix_socket.connect(self.sock.fd, addr)
      if result then
        return true
      else
        return nil, err
      end
    end,
    send = function(self, ...)
      local posix_socket = require("posix.sys.socket")
      local data = flatten(...)
      local result, err, _ = posix_socket.send(self.sock.fd, data)
      if result then
        return #data, nil
      else
        return nil, err
      end
    end,
    receive = function(self, bytes)
      local posix_socket = require("posix.sys.socket")
      local result, err, _ = posix_socket.recv(self.sock.fd, bytes)
      if result then
        return result
      else
        return nil, err
      end
    end,
    settimeout = function(self, t)
      self.timeout = t
    end,
    close = function(self)
      local posix_unistd = require("posix.unistd")
      return posix_unistd.close(self.sock.fd)
    end,
    setkeepalive = function(self)
      return error("You attempted to call setkeepalive on a Unix socket. This method is only available for the ngx cosocket API for releasing a socket back into the connection pool")
    end,
    getreusedtimes = function(self, t)
      return 0
    end,
    sslhandshake = function(self, opts)
      if opts == nil then
        opts = { }
      end
      return error("SSL handshake is not supported over Unix domain sockets")
    end
  }
  create_luaposix_socket = function(...)
    local posix_socket = require("posix.sys.socket")
    local sockfd, err, _ = posix_socket.socket(posix_socket.AF_UNIX, posix_socket.SOCK_STREAM, 0)
    if not (sockfd) then
      error("Failed to create Unix socket: " .. tostring(err))
    end
    local proxy = {
      sock = {
        fd = sockfd
      }
    }
    for k, v in pairs(method_overrides) do
      proxy[k] = v
    end
    return setmetatable(proxy, proxy_mt)
  end
end
local create_luasocket
do
  local flatten
  flatten = require("pgmoon.util").flatten
  local proxy_mt = {
    __index = function(self, key)
      local sock = self.sock
      local original = sock[key]
      if type(original) == "function" then
        local fn
        fn = function(_, ...)
          return original(sock, ...)
        end
        self[key] = fn
        return fn
      else
        return original
      end
    end
  }
  local method_overrides
  method_overrides = {
    send = function(self, ...)
      return self.sock:send(flatten(...))
    end,
    settimeout = function(self, t)
      if t then
        t = t / 1000
      end
      return self.sock:settimeout(t)
    end,
    setkeepalive = function(self)
      return error("You attempted to call setkeepalive on a LuaSocket socket. This method is only available for the ngx cosocket API for releasing a socket back into the connection pool")
    end,
    getreusedtimes = function(self, t)
      return 0
    end,
    sslhandshake = function(self, opts)
      if opts == nil then
        opts = { }
      end
      local ssl = require("ssl")
      local params = {
        mode = "client",
        protocol = "any",
        verify = "none",
        options = {
          "all",
          "no_sslv2",
          "no_sslv3",
          "no_tlsv1"
        }
      }
      for k, v in pairs(opts) do
        params[k] = v
      end
      local sec_sock, err = ssl.wrap(self.sock, params)
      if not (sec_sock) then
        return false, err
      end
      local success
      success, err = sec_sock:dohandshake()
      if not (success) then
        return false, err
      end
      for k, v in pairs(self) do
        if not method_overrides[k] and type(v) == "function" then
          self[k] = nil
        end
      end
      self.sock = sec_sock
      return true
    end
  }
  create_luasocket = function(...)
    local socket = require("socket")
    local proxy = {
      sock = socket.tcp(...)
    }
    for k, v in pairs(method_overrides) do
      proxy[k] = v
    end
    return setmetatable(proxy, proxy_mt)
  end
end
return {
  create_luasocket = create_luasocket,
  create_luaposix_socket = create_luaposix_socket,
  new = function(socket_type)
    if socket_type == nil then
      if ngx and ngx.get_phase() ~= "init" then
        socket_type = "nginx"
      else
        socket_type = "luasocket"
      end
    end
    local socket
    local _exp_0 = socket_type
    if "nginx" == _exp_0 then
      socket = ngx.socket.tcp()
    elseif "luasocket" == _exp_0 then
      socket = create_luasocket()
    elseif "luaposix" == _exp_0 then
      socket = create_luaposix_socket()
    elseif "cqueues" == _exp_0 then
      socket = require("pgmoon.cqueues").CqueuesSocket()
    else
      socket = error("got unknown or unset socket type: " .. tostring(socket_type))
    end
    return socket, socket_type
  end
}
