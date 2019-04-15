if ngx then
  return {
    md5 = ngx.md5
  }
end
local md5
pcall(function()
  local digest = require("openssl.digest")
  local hex_char
  hex_char = function(c)
    return string.format("%02x", string.byte(c))
  end
  local hex
  hex = function(str)
    return (str:gsub(".", hex_char))
  end
  md5 = function(str)
    return hex(digest.new("md5"):final(str))
  end
end)
if not (md5) then
  pcall(function()
    local crypto = require("crypto")
    md5 = function(str)
      return crypto.digest("md5", str)
    end
  end)
end
if not (md5) then
  error("Either luaossl (recommended) or LuaCrypto is required to calculate md5")
end
return {
  md5 = md5
}
