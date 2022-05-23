local rshift, lshift, band, bxor
local load_code
load_code = function(str)
  local sent = false
  return pcall(load(function()
    if sent then
      return nil
    end
    sent = true
    return str
  end))
end
local ok
ok, band = load_code([[  return function(a,b)
    a = a & b
    if a > 0x7FFFFFFF then
      -- extend the sign bit
      a = ~0xFFFFFFFF | a
    end
    return a
  end
]])
if ok then
  local _
  _, bxor = load_code([[    return function(a,b)
      a = a ~ b
      if a > 0x7FFFFFFF then
        -- extend the sign bit
        a = ~0xFFFFFFFF | a
      end
      return a
    end
  ]])
  _, lshift = load_code([[    return function(x,y)
      -- limit to 32-bit shifts
      y = y % 32
      x = x << y
      if x > 0x7FFFFFFF then
        -- extend the sign bit
        x = ~0xFFFFFFFF | x
      end
      return x
    end
  ]])
  _, rshift = load_code([[    return function(x,y)
      y = y % 32
      -- truncate to 32-bit before applying shift
      x = x & 0xFFFFFFFF
      x = x >> y
      if x > 0x7FFFFFFF then
        x = ~0xFFFFFFFF | x
       end
      return x
    end
  ]])
else
  do
    local _obj_0 = require("bit")
    rshift, lshift, band, bxor = _obj_0.rshift, _obj_0.lshift, _obj_0.band, _obj_0.bxor
  end
end
return {
  rshift = rshift,
  lshift = lshift,
  band = band,
  bxor = bxor
}
