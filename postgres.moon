
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
  @NULL: {"NULL"}

  TYPE = flipped {
    status: "S"
    auth_ok: "R"
    backend_key: "K"
    ready_for_query: "Z"
    query: "Q"
    notice: "N"

    row_description: "T"
    data_row: "D"
    command_complete: "C"

    error: "E"
  }

  ERROR_TYPES = flipped {
    severity: "S"
    code: "C"
    message: "M"
    position: "P"
    detail: "D"
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
    local row_desc, data_rows, command_complete

    while true
      t, msg = @receive_message!
      switch t
        when TYPE.data_row
          data_rows or= {}
          insert data_rows, msg
        when TYPE.row_description
          row_desc = msg
        when TYPE.error
          error @parse_error msg
        when TYPE.command_complete
          command_complete = msg
        -- when TYPE.notice
        --   -- TODO: do something with notices
        when TYPE.ready_for_query
          break

    local command, affected_rows

    if command_complete
      command = command_complete\match "^%w+"
      affected_rows = tonumber command_complete\match "%d+%z$"

    if row_desc
      return {} unless data_rows

      fields = @parse_row_desc row_desc
      num_rows = #data_rows
      for i=1,num_rows
        data_rows[i] = @parse_data_row data_rows[i], fields

      if affected_rows and command != "SELECT"
        data_rows.affected_rows = affected_rows

      return data_rows

    if affected_rows
      { :affected_rows }
    else
      true

  parse_error: (err_msg) =>
    local severity, message, detail, position

    offset = 1
    while offset <= #err_msg
      t = err_msg\sub offset, offset
      str = err_msg\match "[^%z]+", offset + 1
      break unless str

      offset += 2 + #str

      switch t
        when ERROR_TYPES.severity
          severity = str
        when ERROR_TYPES.message
          message = str
        when ERROR_TYPES.position
          position = str
        when ERROR_TYPES.detail
          detail = str

    msg = "#{severity}: #{message}"

    if position
      msg = "#{msg} (#{position})"

    if detail
      msg = "#{msg}\n#{detail}"

    msg

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

  parse_data_row: (data_row, fields) =>
    -- 2: number of values
    num_fields = @decode_int data_row\sub(1,2)
    out = {}

    offset = 3
    for i=1,num_fields
      field = fields[i]
      continue unless field
      {field_name, field_type} = field

      -- 4: length of value
      len = @decode_int data_row\sub offset, offset + 3
      offset += 4

      if len < 0
        out[field_name] = @@NULL
        continue

      value = data_row\sub offset, offset + len - 1
      offset += len

      switch field_type
        when "number"
          value = tonumber value
        when "boolean"
          value = value == "t"

      out[field_name] = value

    out

  wait_until_ready: =>
    while true
      t, msg = @receive_message!
      error @parse_error(msg) if TYPE.error == t
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
  pg = Postgres "127.0.0.1", "5432", "postgres", "pgmoon"
  pg\connect!
  -- require("moon").p p\send_query "select 13247 hello, 'yeah' yeah, true boo, false wah, NULL"
  -- require("moon").p p\send_query "select * from user_data"

  db = require "lapis.db"
  import create_table, types from require "lapis.db.schema"

  local query_string
  db.set_backend "raw", (...) ->
    pg\send_query ...

  import p from require "moon"

  print "Insert"
  _insert = db.insert "hello_world", {
    name: "hi"
    count: 100
  }, "id"

  p _insert

  print "Select"
  p db.select "* from hello_world limit 2"

  print "Update none"
  p db.update "hello_world", {
    name: "wedfefefw"
  }, {
    name: "YEAH"
  }

  if type(_insert) == "table"
    print "Update some"
    p db.update "hello_world", {
      name: "wedfefefw"
    }, {
      id: _insert[1].id
    }

  print "Delete none"
  p db.delete "hello_world", {
    name: "wedfefefw"
  }

  if type(_insert) == "table"
    print "Delete one"
    p db.delete "hello_world", {
      id: _insert[1].id
    }

{ :Postgres }

