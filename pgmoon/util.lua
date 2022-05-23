local flatten
do
  local __flatten
  __flatten = function(t, buffer)
    local _exp_0 = type(t)
    if "string" == _exp_0 then
      buffer[#buffer + 1] = t
    elseif "number" == _exp_0 then
      buffer[#buffer + 1] = tostring(t)
    elseif "table" == _exp_0 then
      for _index_0 = 1, #t do
        local thing = t[_index_0]
        __flatten(thing, buffer)
      end
    end
  end
  flatten = function(t)
    local buffer = { }
    __flatten(t, buffer)
    return table.concat(buffer)
  end
end
local encode_base64, decode_base64
if ngx then
  do
    local _obj_0 = ngx
    encode_base64, decode_base64 = _obj_0.encode_base64, _obj_0.decode_base64
  end
else
  local b64, unb64
  do
    local _obj_0 = require("mime")
    b64, unb64 = _obj_0.b64, _obj_0.unb64
  end
  encode_base64 = function(...)
    return (b64(...))
  end
  decode_base64 = function(...)
    return (unb64(...))
  end
end
return {
  flatten = flatten,
  encode_base64 = encode_base64,
  decode_base64 = decode_base64
}
