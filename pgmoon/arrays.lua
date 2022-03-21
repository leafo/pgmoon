local OIDS = {
  boolean = 1000,
  number = 1231,
  string = 1009
}
local PostgresArray
do
  local _class_0
  local _base_0 = { }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "PostgresArray"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  local self = _class_0
  self.__base.pgmoon_serialize = function(v, pg)
    local escaped
    do
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #v do
        local val = v[_index_0]
        if val == pg.NULL then
          _accum_0[_len_0] = "NULL"
        else
          local _exp_0 = type(val)
          if "number" == _exp_0 then
            _accum_0[_len_0] = tostring(val)
          elseif "string" == _exp_0 then
            _accum_0[_len_0] = '"' .. val:gsub('"', [[\"]]) .. '"'
          elseif "boolean" == _exp_0 then
            _accum_0[_len_0] = val and "t" or "f"
          elseif "table" == _exp_0 then
            local _oid, _value
            do
              local v_mt = getmetatable(val)
              if v_mt then
                if v_mt.pgmoon_serialize then
                  _oid, _value = v_mt.pgmoon_serialize(val, pg)
                end
              end
            end
            if _oid then
              _accum_0[_len_0] = _value
            else
              return nil, "table does not implement pgmoon_serialize, can't serialize"
            end
          end
        end
        _len_0 = _len_0 + 1
      end
      escaped = _accum_0
    end
    local type_oid = 0
    for _index_0 = 1, #v do
      local _continue_0 = false
      repeat
        do
          local val = v[_index_0]
          if val == pg.NULL then
            _continue_0 = true
            break
          end
          type_oid = OIDS[type(val)] or type_oid
          break
        end
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
    return type_oid, "{" .. tostring(table.concat(escaped, ",")) .. "}"
  end
  PostgresArray = _class_0
end
getmetatable(PostgresArray).__call = function(self, t)
  return setmetatable(t, self.__base)
end
local default_escape_literal = nil
local insert, concat
do
  local _obj_0 = table
  insert, concat = _obj_0.insert, _obj_0.concat
end
local encode_array
do
  local append_buffer
  append_buffer = function(escape_literal, buffer, values)
    for _index_0 = 1, #values do
      local item = values[_index_0]
      if type(item) == "table" and not getmetatable(item) then
        insert(buffer, "[")
        append_buffer(escape_literal, buffer, item)
        buffer[#buffer] = "]"
        insert(buffer, ",")
      else
        insert(buffer, escape_literal(item))
        insert(buffer, ",")
      end
    end
    return buffer
  end
  encode_array = function(tbl, escape_literal)
    escape_literal = escape_literal or default_escape_literal
    if not (escape_literal) then
      local Postgres
      Postgres = require("pgmoon").Postgres
      default_escape_literal = function(v)
        return Postgres.escape_literal(nil, v)
      end
      escape_literal = default_escape_literal
    end
    local buffer = append_buffer(escape_literal, {
      "ARRAY["
    }, tbl)
    if buffer[#buffer] == "," then
      buffer[#buffer] = "]"
    else
      insert(buffer, "]")
    end
    return concat(buffer)
  end
end
local convert_values
convert_values = function(array, fn, pg)
  for idx, v in ipairs(array) do
    if type(v) == "table" then
      convert_values(v, fn)
    else
      if v == "NULL" then
        array[idx] = pg.NULL
      elseif fn then
        array[idx] = fn(v)
      else
        array[idx] = v
      end
    end
  end
  return array
end
local decode_array
do
  local P, R, S, V, Ct, C, Cs
  do
    local _obj_0 = require("lpeg")
    P, R, S, V, Ct, C, Cs = _obj_0.P, _obj_0.R, _obj_0.S, _obj_0.V, _obj_0.Ct, _obj_0.C, _obj_0.Cs
  end
  local g = P({
    "array",
    array = Ct(V("open") * (V("value") * (P(",") * V("value")) ^ 0) ^ -1 * V("close")),
    value = V("invalid_char") + V("string") + V("array") + V("literal"),
    string = P('"') * Cs((P([[\\]]) / [[\]] + P([[\"]]) / [["]] + (P(1) - P('"'))) ^ 0) * P('"'),
    literal = C((P(1) - S("},")) ^ 1),
    invalid_char = S(" \t\r\n") / function()
      return error("got unexpected whitespace")
    end,
    open = P("{"),
    delim = P(","),
    close = P("}")
  })
  decode_array = function(str, convert_fn, pg)
    local out = (assert(g:match(str), "failed to parse postgresql array"))
    setmetatable(out, PostgresArray.__base)
    return convert_values(out, convert_fn, (pg or require("pgmoon").Postgres))
  end
end
return {
  encode_array = encode_array,
  decode_array = decode_array,
  PostgresArray = PostgresArray
}
