
class PostgresArray

getmetatable(PostgresArray).__call = (t) =>
  setmetatable t, @__base

default_escape_literal = nil

as_array = (val, escape_literal) ->
  return -> encode_array(val, escape_literal)

encode_array = do
  append_buffer = (escape_literal, buffer, values) ->
    for item in *values
      -- plain array
      if type(item) == "table" and not getmetatable(item)
        table.insert buffer, "["
        append_buffer escape_literal, buffer, item
        buffer[#buffer] = "]" -- strips trailing comma
        table.insert buffer, ","
      else
        table.insert buffer, escape_literal item
        table.insert buffer, ","

    buffer

  (tbl, escape_literal) ->
    escape_literal or= default_escape_literal

    unless escape_literal
      import Postgres from require "pgmoon"
      default_escape_literal = (v) ->
        Postgres.escape_literal nil, v

      escape_literal = default_escape_literal

    buffer = append_buffer escape_literal, {"ARRAY["}, tbl

    buffer[#buffer] = "]" -- strips trailing comma
    table.concat buffer

convert_values = (array, fn) ->
  for idx, v in ipairs array
    if type(v) == "table"
      convert_values v, fn
    else
      array[idx] = fn v

  array

decode_array = do
  import P, R, S, V, Ct, C, Cs from require "lpeg"
  g = P {
    "array"

    array: Ct V"open" * (V"value" * (P"," * V"value")^0)^-1 * V"close"
    value: V"invalid_char" + V"string" + V"array" + V"literal"

    string: P'"' * Cs(
      (P([[\\]]) / [[\]] + P([[\"]]) / [["]] + (P(1) - P'"'))^0
    ) * P'"'

    literal: C (P(1) - S"},")^1

    invalid_char: S" \t\r\n" / -> error "got unexpected whitespace"

    open: P"{"
    delim: P","
    close: P"}"
  }

  (str, convert_fn) ->
    out = (assert g\match(str), "failed to parse postgresql array")
    setmetatable out, PostgresArray.__base

    if convert_fn
      convert_values out, convert_fn
    else
      out



{ :as_array, :encode_array, :decode_array, :PostgresArray }

