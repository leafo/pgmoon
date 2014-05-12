if ngx then
  return {
    tcp = ngx.socket.tcp
  }
end
local _flatten
_flatten = function(t, buffer)
  if buffer == nil then
    buffer = ""
  end
  local _exp_0 = type(t)
  if "string" == _exp_0 then
    buffer = buffer .. t
  elseif "table" == _exp_0 then
    for _index_0 = 1, #t do
      local thing = t[_index_0]
      buffer = _flatten(thing, buffer)
    end
  end
  return buffer
end
local socket = require("socket")
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
return {
  tcp = function(...)
    local sock = socket.tcp(...)
    local proxy = setmetatable({
      sock = sock,
      send = function(self, ...)
        return self.sock:send(_flatten(...))
      end,
      getreusedtimes = function(self)
        return 0
      end
    }, proxy_mt)
    return proxy
  end
}
