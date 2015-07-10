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
local decode_array
decode_array = function(pg, str)
  local P, R, S, V, Ct, C
  do
    local _obj_0 = require("lpeg")
    P, R, S, V, Ct, C = _obj_0.P, _obj_0.R, _obj_0.S, _obj_0.V, _obj_0.Ct, _obj_0.C
  end
  local g = P({
    "array",
    array = Ct(V("open") * (V("value") * (P(",") * V("value")) ^ 0) ^ -1 * V("close")),
    value = V("number") + V("string") + V("array"),
    number = R("09") ^ 1 * (P(".") * R("09") ^ 1) ^ -1 / tonumber,
    string = P('"') * C(P([[\\]] + P([[\"]] + P(1)))) ^ 0 * P('"'),
    open = P("{"),
    delim = P(","),
    close = P("}")
  })
  return (assert(g:match(str), "failed to parse postgresql array"))
end
return {
  encode_array = encode_array,
  decode_array = decode_array
}
