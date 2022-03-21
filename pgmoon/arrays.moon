
OIDS = {
  boolean: 1000
  number: 1231
  string: 1009

  -- supplementary types for subtype detection
  array_json: 199
  array_jsonb: 3807
}

is_array = (oid) ->
  for k, v in pairs OIDS
    return true if v == oid

  false

class PostgresArray
  -- the array literal syntax used is different than the "array constructor"
  -- that is used in encode_array below. This is the same format that is parsed by "decode_array"
  -- https://www.postgresql.org/docs/current/arrays.html#ARRAYS-INPUT
  @__base.pgmoon_serialize = (v, pg) ->
    escaped = for val in *v
      if val == pg.NULL
        "NULL"
      else
        switch type(val)
          when "number"
            tostring val
          when "string"
            '"' .. val\gsub('"', [[\"]]) .. '"'
          when "boolean"
            val and "t" or "f"
          when "table"
            -- attempt to serialize recursively
            local _oid, _value
            if v_mt = getmetatable(val)
              if v_mt.pgmoon_serialize
                _oid, _value = v_mt.pgmoon_serialize val, pg

            if _oid
              if is_array(_oid)
                _value
              else
                -- because of array syntax we can't trust the type here so we
                -- must quote it. This may fail for sub-arrays of types not
                -- accounted for in OIDs
                '"' .. _value\gsub('"', [[\"]]) .. '"'
            else
              return nil, "table does not implement pgmoon_serialize, can't serialize"

    type_oid = 0
    for val in *v
      continue if val == pg.NULL
      type_oid = OIDS[type val] or type_oid
      break

    type_oid, "{#{table.concat escaped, ","}}"

getmetatable(PostgresArray).__call = (t) =>
  setmetatable t, @__base

default_escape_literal = nil

import insert, concat from table

encode_array = do
  append_buffer = (escape_literal, buffer, values) ->
    for item in *values
      -- plain array
      if type(item) == "table" and not getmetatable(item)
        insert buffer, "["
        append_buffer escape_literal, buffer, item
        buffer[#buffer] = "]" -- strips trailing comma
        insert buffer, ","
      else
        insert buffer, escape_literal item
        insert buffer, ","

    buffer

  (tbl, escape_literal) ->
    escape_literal or= default_escape_literal

    unless escape_literal
      import Postgres from require "pgmoon"
      default_escape_literal = (v) ->
        Postgres.escape_literal nil, v

      escape_literal = default_escape_literal

    buffer = append_buffer escape_literal, {"ARRAY["}, tbl


    if buffer[#buffer] == ","
      buffer[#buffer] = "]"
    else
      insert buffer, "]"
    concat buffer

convert_values = (array, fn, pg) ->
  for idx, v in ipairs array
    if type(v) == "table"
      convert_values v, fn
    else
      array[idx] = if v == "NULL"
        pg.NULL
      elseif fn
        fn v
      else
        v

  array

-- TODO: this should handle null and booleans
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

  (str, convert_fn, pg) ->
    out = (assert g\match(str), "failed to parse postgresql array")
    setmetatable out, PostgresArray.__base

    convert_values out, convert_fn, (pg or require("pgmoon").Postgres)



{ :encode_array, :decode_array, :PostgresArray }

