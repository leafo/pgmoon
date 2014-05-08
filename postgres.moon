
import insert from table

socket = if _G.ngx
  _G.ngx.socket
else
  require "socket"

_flatten = (t, buffer="") ->
  if _G.ngx
    _flatten = (...) -> ...
    return t

  switch type(t)
    when "string"
      buffer ..= t
    when "table"
      for thing in *t
        buffer = _flatten thing, buffer

  buffer


_len = (thing, t=type(thing)) ->
  switch t
    when "string"
      #thing
    when "table"
      l = 0
      for inner in *thing
        inner_t = type inner
        if inner_t == "string"
          l += #inner
        else
          l += _len inner, inner_t
      l
    else
      error "don't know how to calculate length of #{t}"


_debug_msg = (str) ->
  require("moon").dump [p for p in str\gmatch "[^%z]+"]

flipped = (t) ->
  keys = [k for k in pairs t]
  for key in *keys
    t[t[key]] = key
  t

class Postgres
  TYPE = flipped {
    status: "S"
    auth_ok: "R"
    backend_key: "K"
    ready_for_query: "Z"
    query: "Q"

    row_description: "T"
    data_row: "D"
    close: "C"

    error: "E"
  }

  PG_TYPES = {
    [16]: "boolean"

    [20]: "number" -- int8
    [21]: "number" -- int2
    [23]: "number" -- int4
    [700]: "number" -- float4
    [201]: "number" -- float8
    [1700]: "number" -- numeric
  }

  NULL = "\0"

  import rshift, lshift, band from require "bit"

  new: (@host, @port, @user, @db) =>

  connect: =>
    @sock = socket.tcp!
    ok, err = @sock\connect @host, tonumber @port
    return nil, err unless ok
    success, err = @send_startup_message!
    return nil, err unless success

    @auth!
    @wait_until_ready!

  auth: =>
    t, msg = @receive_message!
    if TYPE.auth_ok == t
      return true

    error "don't know how to auth #{t}"

  send_query: (q) =>
    @send_message TYPE.query, {q, NULL}
    local row_desc, data_rows

    while true
      t, msg = @receive_message!
      switch t
        when TYPE.data_row
          data_rows or= {}
          insert data_rows, msg
        when TYPE.row_description
          row_desc = msg
        when TYPE.error
          error "error: #{msg}"
        when TYPE.ready_for_query
          break
        else
          print t, _debug_msg(msg)

    if row_desc
      @parse_row_desc row_desc

  parse_row_desc: (row_desc) =>
    num_fields = @decode_int row_desc\sub(1,2)
    offset = 3
    fields = for i=1,num_fields
      name = row_desc\match "[^%z]+", offset
      offset += #name + 1
      -- 4: object id of table
      -- 2: attribute number of column (4)

      -- 4: object id of data type (6)
      data_type = @decode_int row_desc\sub offset + 6, offset + 6 + 3
      data_type = PG_TYPES[data_type] or "string"

      -- 2: data type size (10)
      -- 4: type modifier (12)

      -- 2: format code (16)
      -- we only know how to handle text
      format = @decode_int row_desc\sub offset + 16, offset + 16 + 1
      assert 0 == format, "don't know how to handle format"

      offset += 18
      {name, data_type}

    fields

  wait_until_ready: =>
    while true
      t, msg = @receive_message!
      error "error: #{msg}" if TYPE.error == t
      break if TYPE.ready_for_query == t

  receive_message: =>
    t, err = @sock\receive 1
    return nil, "failed to get type: #{err}" unless t
    len, err = @sock\receive 4
    return nil, "failed to get len: #{err}" unless len
    len = @decode_int len
    len -= 4
    msg = @sock\receive len
    t, msg

  send_startup_message: =>
    data = {
      @encode_int 196608
      "user", NULL
      @user, NULL
      "database", NULL
      @db, NULL
      NULL
    }

    @sock\send _flatten {
      @encode_int _len(data) + 4
      data
    }

  send_message: (t, data, len=nil) =>
    len = _len data if len == nil
    len += 4 -- includes the length of the length integer

    @sock\send _flatten {
      t
      @encode_int len
      data
    }

  decode_int: (str, bytes=#str) =>
    switch bytes
      when 4
        d, c, b, a = str\byte 1, 4
        a + lshift(b, 8) + lshift(c, 16) + lshift(d, 24)
      when 2
        b, a = str\byte 1, 2
        a + lshift(b, 8)
      else
        error "don't know how to decode #{bytes} byte(s)"

  -- create big endian binary string of number
  encode_int: (n, bytes=4) =>
    switch bytes
      when 4
        a = band n, 0xff
        b = band rshift(n, 8), 0xff
        c = band rshift(n, 16), 0xff
        d = band rshift(n, 24), 0xff
        string.char d, c, b, a
      else
        error "don't know how to encode #{bytes} byte(s)"

unless ...
  p = Postgres "127.0.0.1", "5432", "postgres", "moonrocks"
  p\connect!
  p\send_query "select 13247 hello, 'yeah' yeah"

{ :Postgres }

