
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


kdf_derive_sha256 = (str, salt, i) ->
  openssl_kdf = require "openssl.kdf"
  import decode_base64 from require "pgmoon.util"

  salt = decode_base64 salt

  key, err = openssl_kdf.derive {
    type: "PBKDF2"
    md: "sha256"
    salt: salt
    iter: i
    pass: str
    outlen: 32 -- our H() produces a 32 byte hash value (SHA-256)
  }

  unless key
    return nil, "failed to derive pbkdf2 key: #{err}"

  key

{ :md5, :hmac_sha256, :digest_sha256, :kdf_derive_sha256 }
