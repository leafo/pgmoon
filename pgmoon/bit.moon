local load, rshift, lshift, band, ok, _

load = load
if loadstring then
  load = loadstring

ok, rshift = pcall(load("return function(x,n) return x >> n end"))
if ok then
  _, lshift = pcall(load("return function(x,n) return x << n end"))
  _, band   = pcall(load("return function(a,b) return a & b end"))
else
  import rshift, lshift, band from require "bit"

return {
  rshift: rshift
  lshift: lshift
  band: band
}

