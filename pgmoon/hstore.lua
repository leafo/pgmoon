local PostgresHstore
do
  local _class_0
  local _base_0 = { }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "PostgresHstore"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  PostgresHstore = _class_0
end
getmetatable(PostgresHstore).__call = function(self, t)
  return setmetatable(t, self.__base)
end
local encode_hstore
do
  encode_hstore = function(tbl, escape_literal)
    if not (escape_literal) then
      local Postgres
      Postgres = require("pgmoon").Postgres
      local default_escape_literal
      default_escape_literal = function(v)
        return Postgres.escape_literal(nil, v)
      end
      escape_literal = default_escape_literal
    end
    local buffer = { }
    for k, v in pairs(tbl) do
      table.insert(buffer, '"' .. k .. '"=>"' .. v .. '"')
    end
    return escape_literal(table.concat(buffer, ", "))
  end
end
local decode_hstore
do
  local P, R, S, V, Ct, C, Cs, Cg, Cf
  do
    local _obj_0 = require("lpeg")
    P, R, S, V, Ct, C, Cs, Cg, Cf = _obj_0.P, _obj_0.R, _obj_0.S, _obj_0.V, _obj_0.Ct, _obj_0.C, _obj_0.Cs, _obj_0.Cg, _obj_0.Cf
  end
  local g = P({
    "hstore",
    hstore = Cf(Ct("") * (V("pair") * (V("delim") * V("pair")) ^ 0) ^ -1, rawset) * -1,
    pair = Cg(V("value") * "=>" * (V("value") + V("null"))),
    value = V("invalid_char") + V("string"),
    string = P('"') * Cs((P([[\\]]) / [[\]] + P([[\"]]) / [["]] + (P(1) - P('"'))) ^ 0) * P('"'),
    null = C('NULL'),
    invalid_char = S(" \t\r\n") / function()
      return error("got unexpected whitespace")
    end,
    delim = P(", ")
  })
  decode_hstore = function(str, convert_fn)
    local out = (assert(g:match(str), "failed to parse postgresql hstore"))
    setmetatable(out, PostgresHstore.__base)
    return out
  end
end
return {
  encode_hstore = encode_hstore,
  decode_hstore = decode_hstore,
  PostgresHstore = PostgresHstore
}
