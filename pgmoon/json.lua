local default_escape_literal = nil
local as_json
as_json = function(val, escape_literal)
  return function()
    return encode_json(val, escape_literal)
  end
end
local encode_json
encode_json = function(tbl, escape_literal)
  escape_literal = escape_literal or default_escape_literal
  local json = require("cjson")
  if not (escape_literal) then
    local Postgres
    Postgres = require("pgmoon").Postgres
    default_escape_literal = function(v)
      return Postgres.escape_literal(nil, v)
    end
    escape_literal = default_escape_literal
  end
  local enc = json.encode(tbl)
  return escape_literal(enc)
end
local decode_json
decode_json = function(str)
  local json = require("cjson")
  return json.decode(str)
end
return {
  as_json = as_json,
  encode_json = encode_json,
  decode_json = decode_json
}
