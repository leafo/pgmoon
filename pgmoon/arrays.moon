
encode_array = do
  append_buffer = (pg, buffer, values) ->
    for item in *values
      if type(item) == "table"
        table.insert buffer, "["
        append_buffer pg, buffer, item
        buffer[#buffer] = "]" -- strips trailing comma
        table.insert buffer, ","
      else
        table.insert buffer, pg\escape_literal item
        table.insert buffer, ","

    buffer

  (pg, tbl) ->
    buffer = append_buffer pg, {"ARRAY["}, tbl

    buffer[#buffer] = "]" -- strips trailing comma
    table.concat buffer



{:encode_array, :decode_array}

