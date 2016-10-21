local luasocket
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
  local overrides = {
    send = true,
    getreusedtimes = true,
    sslhandshake = true,
    settimeout = true
  }
  luasocket = {
    tcp = function(...)
      local socket = require("socket")
      local sock = socket.tcp(...)
      local proxy = setmetatable({
        sock = sock,
        send = function(self, ...)
          return self.sock:send(flatten(...))
        end,
        getreusedtimes = function(self)
          return 0
        end,
        settimeout = function(self, t)
          if t then
            t = t / 1000
          end
          return self.sock:settimeout(t)
        end,
        sslhandshake = function(self, _, _, verify, _, opts)
          if opts == nil then
            opts = { }
          end
          local ssl = require("ssl")
          local params = {
            mode = "client",
            protocol = "tlsv1",
            key = opts.key,
            certificate = opts.cert,
            cafile = opts.cafile,
            verify = verify and "peer" or "none",
            options = "all"
          }
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
            if not (type(v) ~= "function" or overrides[k]) then
              self[k] = nil
            end
          end
          self.sock = sec_sock
          return true
        end
      }, proxy_mt)
      return proxy
    end
  }
end
return {
  new = function()
    if ngx and ngx.get_phase() ~= "init" then
      return ngx.socket.tcp(), "nginx"
    else
      return luasocket.tcp(), "luasocket"
    end
  end
}
