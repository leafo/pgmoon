
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


hmac_sha256 = if pcall -> require "openssl.hmac"
  (key, str) ->
    openssl_hmac = require("openssl.hmac")
    hmac = assert openssl_hmac.new(key, "sha256")

    hmac\update str
    assert hmac\final!
elseif pcall -> require "resty.openssl.hmac"
  (key, str) ->
    openssl_hmac = require("resty.openssl.hmac")
    hmac = assert openssl_hmac.new(key, "sha256")

    hmac\update str
    assert hmac\final!
else
  -> error "Either luaossl or resty.openssl is required to calculate hmac sha256 digest"


digest_sha256 = if pcall -> require "openssl.digest"
  (str) ->
    digest = assert require("openssl.digest").new("sha256")
    digest\update str
    assert digest\final!
elseif pcall -> require "resty.sha256"
  (str) ->
    digest = assert require("resty.sha256")\new()
    digest\update str
    assert digest\final!
elseif pcall -> require "resty.openssl.digest"
  (str) ->
    digest = assert require("resty.openssl.digest").new("sha256")
    digest\update str
    assert digest\final!
else
  -> error "Either luaossl or resty.openssl is required to calculate sha256 digest"


kdf_derive_sha256 = if pcall -> require "openssl.kdf"
  (str, salt, i) ->
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
elseif pcall -> require "resty.openssl.kdf"
  (str, salt, i) ->
    openssl_kdf = require "resty.openssl.kdf"
    import decode_base64 from require "pgmoon.util"

    salt = decode_base64 salt

    key, err = openssl_kdf.derive {
      type: openssl_kdf.PBKDF2
      md: "sha256"
      salt: salt
      pbkdf2_iter: i
      pass: str
      outlen: 32 -- our H() produces a 32 byte hash value (SHA-256)
    }

    unless key
      return nil, "failed to derive pbkdf2 key: #{err}"

    key
else
  -> error "Either luaossl or resty.openssl is required to derive pbkdf2 key"


random_bytes = if pcall -> require "openssl.rand"
  require("openssl.rand").bytes
elseif pcall -> require "resty.random"
  require("resty.random").bytes
elseif pcall -> require "resty.openssl.rand"
  require("resty.openssl.rand").bytes
else
  -> error "Either luaossl or resty.openssl is required to generate random bytes"


x509_digest = if pcall -> require "openssl.x509"
  x509 = require "openssl.x509"
  (pem, hash_type) -> x509.new(pem, "PEM")\digest(hash_type, "s")
elseif pcall -> require "resty.openssl.x509"
  x509 = require "resty.openssl.x509"
  (pem, hash_type) -> x509.new(pem, "PEM")\digest(hash_type)
else
  -> error "Either luaossl or resty.openssl is required to calculate x509 digest"


{ :md5, :hmac_sha256, :digest_sha256, :kdf_derive_sha256, :random_bytes, :x509_digest }
