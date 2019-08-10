
if ngx
  return { md5: ngx.md5 }

local md5

pcall ->
  digest = require "openssl.digest"

  hex_char = (c) -> string.format "%02x", string.byte c
  hex = (str) -> (str\gsub ".", hex_char)

  md5 = (str) ->
    hex digest.new("md5")\final str

unless md5
  pcall ->
    crypto = require "crypto"

    md5 = (str) ->
      crypto.digest "md5", str

unless md5
  error "Either luaossl (recommended) or LuaCrypto is required to calculate md5"

{ :md5 }
