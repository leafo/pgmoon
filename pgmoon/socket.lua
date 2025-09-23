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
    elseif "cqueues" == _exp_0 then
      socket = require("pgmoon.cqueues").CqueuesSocket()
    elseif "luaposix" == _exp_0 then
      socket = require("pgmoon.posix_socket").PosixSocket()
    else
      socket = error("got unknown or unset socket type: " .. tostring(socket_type))
    end
    return socket, socket_type
  end
}
