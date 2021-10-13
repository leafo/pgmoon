local flatten
flatten = require("pgmoon.util").flatten
local CqueuesSocket
do
  local _class_0
  local _base_0 = {
    connect = function(self, host, port, opts)
      local socket = require("cqueues.socket")
      local errno = require("cqueues.errno")
      self.sock = socket.connect({
        host = host,
        port = port
      })
      if self.timeout then
        self.sock:settimeout(self.timeout)
      end
      self.sock:setmode("bn", "bn")
      local success, err = self.sock:connect()
      if not (success) then
        return nil, errno.strerror(err)
      end
      return true
    end,
    sslhandshake = function(self)
      return self.sock:starttls()
    end,
    getpeercertificate = function(self)
      local ssl = assert(self.sock:checktls())
      return assert(ssl:getPeerCertificate(), "no peer certificate available")
    end,
    send = function(self, ...)
      return self.sock:write(flatten(...))
    end,
    receive = function(self, ...)
      return self.sock:read(...)
    end,
    close = function(self)
      return self.sock:close()
    end,
    settimeout = function(self, t)
      if t then
        t = t / 1000
      end
      if self.sock then
        return self.sock:settimeout(t)
      else
        self.timeout = t
      end
    end,
    getreusedtimes = function(self)
      return 0
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "CqueuesSocket"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  CqueuesSocket = _class_0
end
return {
  CqueuesSocket = CqueuesSocket
}
