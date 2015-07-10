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
return {
  encode_array = encode_array,
  decode_array = decode_array
}
