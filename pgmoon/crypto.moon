
if ngx
  return { md5: ngx.md5 }

crypto = require "crypto"

md5 = (str) ->
  crypto.digest "md5", str

{ :md5 }
