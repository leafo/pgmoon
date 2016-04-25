socket = require "pgmoon.socket"
import insert from table
import rshift, lshift, band from require "bit"

VERSION = "1.4.0"

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

MSG_TYPE = flipped {
  status: "S"
  auth: "R"
  backend_key: "K"
  ready_for_query: "Z"
  query: "Q"
  notice: "N"

  password: "p"

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
  [17]: "bytea"

  [20]: "number" -- int8
  [21]: "number" -- int2
  [23]: "number" -- int4
  [700]: "number" -- float4
  [701]: "number" -- float8
  [1700]: "number" -- numeric

  -- arrays
  [1000]: "array_boolean" -- bool array

  [1005]: "array_number" -- int2 array
  [1007]: "array_number" -- int4 array
  [1016]: "array_number" -- int8 array
  [1021]: "array_number" -- float4 array
  [1022]: "array_number" -- float8 array
  [1231]: "array_number" -- numeric array

  [1009]: "array_string" -- text array
  [1015]: "array_string" -- varchar array
  [1002]: "array_string" -- char array
  [1014]: "array_string" -- bpchar array
  [2951]: "array_string" -- uuid array

  [114]: "json" -- json
  [3802]: "json" -- jsonb
}

NULL = "\0"

tobool = (str) ->
  str == "t"

class Postgres
  convert_null: false
  NULL: {"NULL"}

  user: "postgres"
  host: "127.0.0.1"
  port: "5432"

  -- custom types supplementing PG_TYPES
  type_deserializers: {
    json: (val, name) =>
      import decode_json from require "pgmoon.json"
      decode_json val

    bytea: (val, name) =>
      @decode_bytea val

    array_boolean: (val, name) =>
      import decode_array from require "pgmoon.arrays"
      decode_array val, tobool

    array_number: (val, name) =>
      import decode_array from require "pgmoon.arrays"
      decode_array val, tonumber

    array_string: (val, name) =>
      import decode_array from require "pgmoon.arrays"
      decode_array val
  }

  new: (opts) =>
    if opts
      @user = opts.user
      @host = opts.host
      @database = opts.database
      @port = opts.port
      @password = opts.password
      @ssl = opts.ssl
      @ssl_verify = opts.ssl_verify

  connect: =>
    @sock = socket.new!
    ok, err = @sock\connect @host, @port
    return nil, err unless ok

    if @sock\getreusedtimes! == 0
      if @ssl
        success, err = @send_ssl_request!
        return nil, err unless success
      
        has_ssl, err = @sock\receive 1
        if has_ssl == "S"
          success, err = @sock\sslhandshake false, @host, @ssl_verify
          return nil, err unless success
        else
          return nil, "Server does not support SSL"
        
      success, err = @send_startup_message!
      return nil, err unless success
      success, err = @auth!
      return nil, err unless success

      success, err = @wait_until_ready!
      return nil, err unless success

    true

  disconnect: =>
    sock = @sock
    @sock = nil
    sock\close!

  keepalive: (...) =>
    sock = @sock
    @sock = nil
    sock\setkeepalive ...

  auth: =>
    t, msg = @receive_message!
    return nil, msg unless t

    unless MSG_TYPE.auth == t
      @disconnect!

      if MSG_TYPE.error == t
        return nil, @parse_error msg

      error "unexpected message during auth: #{t}"

    auth_type = @decode_int msg, 4
    switch auth_type
      when 0 -- trust
        true
      when 3 -- cleartext password
        @cleartext_auth msg
      when 5 -- md5 password
        @md5_auth msg
      else
        error "don't know how to auth: #{auth_type}"

  cleartext_auth: (msg) =>
    assert @password, "missing password, required for connect"

    @send_message MSG_TYPE.password, {
      @password
      NULL
    }

    @check_auth!

  md5_auth: (msg) =>
    import md5 from require "pgmoon.crypto"
    salt = msg\sub 5, 8
    assert @password, "missing password, required for connect"

    @send_message MSG_TYPE.password, {
      "md5"
      md5 md5(@password .. @user) .. salt
      NULL
    }

    @check_auth!

  check_auth: =>
    t, msg = @receive_message!
    return nil, msg unless t

    switch t
      when MSG_TYPE.error
        nil, @parse_error msg
      when MSG_TYPE.auth
        true
      else
        error "unknown response from auth"

  query: (q) =>
    @send_message MSG_TYPE.query, {q, NULL}
    local row_desc, data_rows, command_complete, err_msg

    local result
    num_queries = 0

    while true
      t, msg = @receive_message!
      return nil, msg unless t
      switch t
        when MSG_TYPE.data_row
          data_rows or= {}
          insert data_rows, msg
        when MSG_TYPE.row_description
          row_desc = msg
        when MSG_TYPE.error
          err_msg = msg
        when MSG_TYPE.command_complete
          command_complete = msg
          next_result = @format_query_result row_desc, data_rows, command_complete
          num_queries += 1

          if num_queries == 1
            result = next_result
          elseif num_queries == 2
            result = { result, next_result }
          else
            insert result, next_result

          row_desc, data_rows, command_complete = nil
        when MSG_TYPE.ready_for_query
          break
        -- when MSG_TYPE.notice
        --   -- TODO: do something with notices

    if err_msg
      return nil, @parse_error(err_msg), result, num_queries

    result, num_queries

  format_query_result: (row_desc, data_rows, command_complete) =>
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
        out[field_name] = @NULL if @convert_null
        continue

      value = data_row\sub offset, offset + len - 1
      offset += len

      switch field_type
        when "number"
          value = tonumber value
        when "boolean"
          value = value == "t"
        when "string"
          nil
        else
          if fn = @type_deserializers[field_type]
            value = fn @, value, field_type

      out[field_name] = value

    out

  wait_until_ready: =>
    while true
      t, msg = @receive_message!
      return nil, msg unless t

      if MSG_TYPE.error == t
        @disconnect!
        return nil, @parse_error(msg)

      break if MSG_TYPE.ready_for_query == t

    true

  receive_message: =>
    t, err = @sock\receive 1
    unless t
      @disconnect!
      return nil, "receive_message: failed to get type: #{err}"

    len, err = @sock\receive 4

    unless len
      @disconnect!
      return nil, "receive_message: failed to get len: #{err}"

    len = @decode_int len
    len -= 4
    msg = @sock\receive len
    t, msg

  send_startup_message: =>
    assert @user, "missing user for connect"
    assert @database, "missing database for connect"

    data = {
      @encode_int 196608
      "user", NULL
      @user, NULL
      "database", NULL
      @database, NULL
      NULL
    }

    @sock\send {
      @encode_int _len(data) + 4
      data
    }

  send_ssl_request: =>

    @sock\send {
      @encode_int 8
      @encode_int 80877103
    }

  send_message: (t, data, len=nil) =>
    len = _len data if len == nil
    len += 4 -- includes the length of the length integer

    @sock\send {
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

  decode_bytea: (str) =>
    if str\sub(1, 2) == '\\x'
      str\sub(3)\gsub '..', (hex) ->
        string.char tonumber hex, 16
    else
      str\gsub '\\(%d%d%d)', (oct) ->
        string.char tonumber oct, 8

  encode_bytea: (str) =>
    string.format "E'\\\\x%s'", str\gsub '.', (byte) ->
        string.format '%02x', string.byte byte

  escape_identifier: (ident) =>
    '"' ..  (tostring(ident)\gsub '"', '""') .. '"'

  escape_literal: (val) =>
    switch type val
      when "number"
        return tostring val
      when "string"
        return "'#{(val\gsub "'", "''")}'"
      when "boolean"
        return val and "TRUE" or "FALSE"

    error "don't know how to escape value: #{val}"

  __tostring: =>
    "<Postgres socket: #{@sock}>"

{ :Postgres, new: Postgres, :VERSION }

