
if ngx
  return { md5: ngx.md5 }

digest = require "openssl.digest"

md5 = nil

if digest
  to_hex = (str) ->
    string.gsub str, '.', (c) ->
      string.format "%02x", string.byte c

  md5 = (str) ->
    to_hex digest.new("md5")\final(str)
else
  crypto = require "crypto"
  md5 = (str) ->
    crypto.digest "md5", str

{ :md5 }
