local rshift, lshift, band, ok, _
local string_loader


-- lua5.1 has separate 'loadstring' and 'load'
-- functions ('load' doesn't accept strings).
-- This provides a function that 'load' can use,
-- and will work on all versions of lua

string_loader = (str) ->
  sent = false
  return ->
    if sent then
      return nil
    sent = true
    return str


-- use load to treat as a string to prevent
-- parse errors under lua < 5.3

-- luajit uses 32-bit integers for bitwise ops, but lua5.3+
-- uses 32-bit or 64-bit integers, so these wrappers will
-- truncate results and/or extend the sign, as appropriate
-- to match luajit's behavior.
ok, band = pcall(load(string_loader([[
  return function(a,b)
    a = a & b
    if a > 0x7FFFFFFF then
      -- extend the sign bit
      a = ~0xFFFFFFFF | a
    end
    return a
  end
]])))

if ok then
  _, lshift = pcall(load(string_loader([[
    return function(x,y)
      -- limit to 32-bit shifts
      y = y % 32
      x = x << y
      if x > 0x7FFFFFFF then
        -- extend the sign bit
        x = ~0xFFFFFFFF | x
      end
      return x
    end
  ]])))
  _, rshift = pcall(load(string_loader([[
    return function(x,y)
      y = y % 32
      -- truncate to 32-bit before applying shift
      x = x & 0xFFFFFFFF
      x = x >> y
      if x > 0x7FFFFFFF then
        x = ~0xFFFFFFFF | x
       end
      return x
    end
  ]])))
else
  import rshift, lshift, band from require "bit"

return {
  rshift: rshift
  lshift: lshift
  band: band
}

