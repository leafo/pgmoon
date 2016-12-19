default_escape_literal = nil

as_json = (val, escape_literal) ->
  return -> encode_json(val, escape_literal)

encode_json = (tbl, escape_literal) ->
  escape_literal or= default_escape_literal
  json = require "cjson"

  unless escape_literal
    import Postgres from require "pgmoon"
    default_escape_literal = (v) ->
      Postgres.escape_literal nil, v

    escape_literal = default_escape_literal

  enc = json.encode tbl
  escape_literal enc

decode_json = (str) ->
  json = require "cjson"
  json.decode str

{ :as_json :encode_json, :decode_json }
