local l, rshift, lshift, band, ok, _

l = load
if loadstring then
  l = loadstring

ok, rshift = pcall(l("return function(x,n) return x >> n end"))
if ok then
  _, lshift = pcall(l("return function(x,n) return x << n end"))
  _, band   = pcall(l("return function(a,b) return a & b end"))
else
  import rshift, lshift, band from require "bit"

return {
  rshift: rshift
  lshift: lshift
  band: band
}

