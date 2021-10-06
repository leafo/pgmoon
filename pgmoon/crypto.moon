
md5 = if ngx
  ngx.md5
elseif pcall -> require "openssl.digest"
  openssl_digest = require "openssl.digest"
  hex_char = (c) -> string.format "%02x", string.byte c
  hex = (str) -> (str\gsub ".", hex_char)

  (str) -> hex openssl_digest.new("md5")\final str
elseif pcall -> require "crypto"
  crypto = require "crypto"
  (str) -> crypto.digest "md5", str
else
  -> error "Either luaossl (recommended) or LuaCrypto is required to calculate md5"

hmac_sha256 = (key, str) ->
  openssl_hmac = require("openssl.hmac")
  hmac = assert openssl_hmac.new(key, "sha256")

  hmac\update str
  assert hmac\final!

digest_sha256 = (str) ->
  digest = assert require("openssl.digest").new("sha256")
  digest\update str
  assert digest\final!

{ :md5, :hmac_sha256, :digest_sha256 }
