default_escape_literal = nil

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

{ :encode_json, :decode_json }
