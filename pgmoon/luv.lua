local flatten
flatten = require("pgmoon.util").flatten
local luv 
luv = require 'luv'

local LuvSocket
do
  local _class_0
  local _buffer = function() return setmetatable({buff={}, buff_sz=0}, {
    __call = function(self, len)
        while self.buff_sz < len do luv.run 'once' end 
        local data = table.concat(self.buff) -- our buffer 
        local chunk = data:sub(1, len or -1) -- chunk with requested length  
        local remain = data:sub(#chunk+1,-1)  -- remaining data
        self.buff, self.buff_sz = {remain}, #remain -- remaining data size
        return chunk 
    end,
    __add = function(self, chunk) 
        table.insert(self.buff, chunk) -- insert chunk to buffer
        self.buff_sz = self.buff_sz + #chunk -- recalculate size
        return self
    end,
  }) end 
  local _base_0 = {
    connect = function(self, host, port, opts)
      self.buffer = self.buffer or _buffer()
      self.sock = self.sock or luv.new_tcp()
      if not self.sock:is_readable() then 
        self.sock:connect(host, port, function(...) self.sock:read_start(function(err, chunk) self.buffer = (not err) and (self.buffer+chunk) or error(err) end) end)
        luv.run('once')
      end
      return true
    end,
    sslhandshake = function(self)
      return false
    end,
    send = function(self, ...)
      self.sock:write(flatten(...))
      luv.run('once')
      return true
    end,
    receive = function(self, ...)      
      return self.buffer(...)
    end,
    close = function(self)
      return self.sock:close()
    end,
    settimeout = function(self, t)
        self.timeout = t
    end,
    getreusedtimes = function(self)
      return 0
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "LuvSocket"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  LuvSocket = _class_0
end
return {
  LuvSocket = LuvSocket
}
