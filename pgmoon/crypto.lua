if ngx then
  return {
    md5 = ngx.md5
  }
end
local digest = require("openssl.digest")
local md5 = nil
if digest then
  local to_hex
  to_hex = function(str)
    return string.gsub(str, '.', function(c)
      return string.format("%02x", string.byte(c))
    end)
  end
  md5 = function(str)
    return to_hex(digest.new("md5"):final(str))
  end
else
  local crypto = require("crypto")
  md5 = function(str)
    return crypto.digest("md5", str)
  end
end
return {
  md5 = md5
}
