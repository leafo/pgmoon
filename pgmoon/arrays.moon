
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

decode_array = do
  import P, R, S, V, Ct, C, Cs from require "lpeg"
  g = P {
    "array"

    array: Ct V"open" * (V"value" * (P"," * V"value")^0)^-1 * V"close"
    value: V"invalid_char" + V"number" + V"string" + V"array" + V"literal"

    number: R"09"^1 * (P"." * R"09"^1)^-1 / tonumber
    string: P'"' * Cs(
      (P([[\\]]) / [[\]] + P([[\"]]) / [["]] + (P(1) - P'"'))^0
    ) * P'"'

    literal: C (P(1) - S"},")^1

    invalid_char: S" \t\r\n" / -> error "got unexpected whitespace"

    open: P"{"
    delim: P","
    close: P"}"
  }

  (pg, str) ->
    (assert g\match(str), "failed to parse postgresql array")

{:encode_array, :decode_array}

