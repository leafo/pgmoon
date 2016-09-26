
class PostgresHstore

getmetatable(PostgresHstore).__call = (t) =>
  setmetatable t, @__base

encode_hstore = do
  (tbl, escape_literal) ->
    escape_literal or= default_escape_literal

    unless escape_literal
      import Postgres from require "pgmoon"
      default_escape_literal = (v) ->
        Postgres.escape_literal nil, v

      escape_literal = default_escape_literal

    buffer = {}
    for k, v in pairs(tbl)
      table.insert buffer, '"' .. k .. '"=>"' .. v .. '"'

    escape_literal table.concat buffer, ", "

decode_hstore = do
  import P, R, S, V, Ct, C, Cs, Cg, Cf from require "lpeg"
  g = P {
    "hstore"

    hstore: Cf(Ct("") * (V"pair" * (V"delim" * V"pair")^0)^-1, rawset) * -1
    pair: Cg(V"value" * "=>" * (V"value" + V"null"))
    value: V"invalid_char" + V"string"

    string: P'"' * Cs(
      (P([[\\]]) / [[\]] + P([[\"]]) / [["]] + (P(1) - P'"'))^0
    ) * P'"'

    null: C'NULL'

    invalid_char: S" \t\r\n" / -> error "got unexpected whitespace"

    delim: P", "
  }

  (str, convert_fn) ->
    out = (assert g\match(str), "failed to parse postgresql hstore")
    setmetatable out, PostgresHstore.__base

    out



{ :encode_hstore, :decode_hstore, :PostgresHstore }

