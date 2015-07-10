local encode_array
do
  local append_buffer
  append_buffer = function(pg, buffer, values)
    for _index_0 = 1, #values do
      local item = values[_index_0]
      if type(item) == "table" then
        table.insert(buffer, "[")
        append_buffer(pg, buffer, item)
        buffer[#buffer] = "]"
        table.insert(buffer, ",")
      else
        table.insert(buffer, pg:escape_literal(item))
        table.insert(buffer, ",")
      end
    end
    return buffer
  end
  encode_array = function(pg, tbl)
    local buffer = append_buffer(pg, {
      "ARRAY["
    }, tbl)
    buffer[#buffer] = "]"
    return table.concat(buffer)
  end
end
local convert_values
convert_values = function(array, fn)
  for idx, v in ipairs(array) do
    if type(v) == "table" then
      convert_values(v, fn)
    else
      array[idx] = fn(v)
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
    value = V("invalid_char") + V("number") + V("string") + V("array") + V("literal"),
    number = C(R("09") ^ 1 * (P(".") * R("09") ^ 1) ^ -1),
    string = P('"') * Cs((P([[\\]]) / [[\]] + P([[\"]]) / [["]] + (P(1) - P('"'))) ^ 0) * P('"'),
    literal = C((P(1) - S("},")) ^ 1),
    invalid_char = S(" \t\r\n") / function()
      return error("got unexpected whitespace")
    end,
    open = P("{"),
    delim = P(","),
    close = P("}")
  })
  decode_array = function(pg, str, convert_fn)
    local out = (assert(g:match(str), "failed to parse postgresql array"))
    if convert_fn then
      return convert_values(out, convert_fn)
    else
      return out
    end
  end
end
return {
  encode_array = encode_array,
  decode_array = decode_array
}
