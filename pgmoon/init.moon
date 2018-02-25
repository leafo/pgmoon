socket = require "pgmoon.socket"
import insert from table

unpack = table.unpack or unpack

VERSION = "1.8.0"

export bit32  -- Use Lua 5.2 bit32 if available. Polyfill otherwise.
if bit32 == nil
  bit32 = require "bit"
lshift, rshift, band = bit32.lshift, bit32.rshift, bit32.band

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

gen_escape = (ref) ->
  return (val) -> ref\escape_literal(val)

MSG_TYPE = flipped {
  status: "S"
  auth: "R"
  backend_key: "K"
  ready_for_query: "Z"
  query: "Q"
  notice: "N"
  notification: "A"

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
  schema: "s"
  table: "t"
  constraint: "n"
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

  [114]: "json" -- json
  [3802]: "json" -- jsonb

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

  [199]: "array_json" -- json array
  [3807]: "array_json" -- jsonb array
}

NULL = "\0"

tobool = (str) ->
  str == "t"

class Postgres
  convert_null: false
  NULL: {"NULL"}
  :PG_TYPES

  user: "postgres"
  host: "127.0.0.1"
  port: "5432"
  ssl: false

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

    array_json: (val, name) =>
      import decode_array from require "pgmoon.arrays"
      import decode_json from require "pgmoon.json"
      decode_array val, decode_json

    hstore: (val, name) =>
      import decode_hstore from require "pgmoon.hstore"
      decode_hstore val
  }

  set_type_oid: (oid, name) =>
    unless rawget(@, "PG_TYPES")
      @PG_TYPES = {k,v for k,v in pairs @PG_TYPES}

    @PG_TYPES[assert tonumber oid] = name

  setup_hstore: =>
    res = unpack @query "SELECT oid FROM pg_type WHERE typname = 'hstore'"
    assert res, "hstore oid not found"
    @set_type_oid tonumber(res.oid), "hstore"

  new: (opts) =>
    @sock, @sock_type = socket.new opts and opts.socket_type

    if opts
      @user = opts.user
      @host = opts.host
      @database = opts.database
      @port = opts.port
      @password = opts.password
      @ssl = opts.ssl
      @ssl_verify = opts.ssl_verify
      @ssl_required = opts.ssl_required
      @pool_name = opts.pool
      @luasec_opts = {
        key: opts.key
        cert: opts.cert
        cafile: opts.cafile
      }

  connect: =>
    opts = if @sock_type == "nginx"
      {
        pool: @pool_name or "#{@host}:#{@port}:#{@database}"
      }

    ok, err = @sock\connect @host, @port, opts
    return nil, err unless ok

    if @sock\getreusedtimes! == 0
      if @ssl
        success, err = @send_ssl_message!
        return nil, err unless success

      success, err = @send_startup_message!
      return nil, err unless success

      success, err = @auth!
      return nil, err unless success

      success, err = @wait_until_ready!
      return nil, err unless success

    true

  settimeout: (...) =>
    @sock\settimeout ...

  disconnect: =>
    @sock\close!

  keepalive: (...) =>
    if @sock.setkeepalive
      return @sock\setkeepalive ...
    else
      error "socket implementation #{@sock_type} does not support keepalive"

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

  query: (q, ...) =>
    num_values = #{...}
    -- Only process placeholders if there are values to fill them
    -- Prepared statements can have placeholders if there are no values
    if q\find "$#{tostring(num_values)}"
      values = {}
      default_escape = gen_escape(self)
      for v in *{...}
        type_v = type(v)
        if v == nil or v == @NULL
          insert values, "NULL"  -- skip the extra function call
        elseif type_v == "function"
          insert values, v default_escape
        else
          insert values, @escape_literal v
      q = q\gsub '$(%d+)', (m) ->
        values[tonumber m]
    elseif num_values > 0
      error "#{num_values} values but missing associated query placeholder(s)"

    @post q
    local row_desc, data_rows, command_complete, err_msg

    local result, notifications
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
        when MSG_TYPE.notification
          notifications = {} unless notifications
          insert notifications, @parse_notification(msg)
        -- when MSG_TYPE.notice
        -- TODO: do something with notices

    if err_msg
      return nil, @parse_error(err_msg), result, num_queries, notifications

    result, num_queries, notifications

  post: (q) =>
    @send_message MSG_TYPE.query, {q, NULL}

  wait_for_notification: =>
    while true
      t, msg = @receive_message!
      return nil, msg unless t
      switch t
        when MSG_TYPE.notification
          return @parse_notification(msg)

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

    error_data = {}

    offset = 1
    while offset <= #err_msg
      t = err_msg\sub offset, offset
      str = err_msg\match "[^%z]+", offset + 1
      break unless str

      offset += 2 + #str

      if field = ERROR_TYPES[t]
        error_data[field] = str

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

    msg, error_data

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
      data_type = @PG_TYPES[data_type] or "string"

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

  parse_notification: (msg) =>
    pid = @decode_int msg\sub 1, 4
    offset = 4

    channel, payload = msg\match "^([^%z]+)%z([^%z]*)%z$", offset + 1

    unless channel
      error "parse_notification: failed to parse notification"

    {
      operation: "notification"
      pid: pid
      channel: channel
      payload: payload
    }

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
      "application_name", NULL
      "pgmoon", NULL
      NULL
    }

    @sock\send {
      @encode_int _len(data) + 4
      data
    }

  send_ssl_message: =>
    success, err = @sock\send {
      @encode_int 8,
      @encode_int 80877103
    }
    return nil, err unless success

    t, err = @sock\receive 1
    return nil, err unless t

    if t == MSG_TYPE.status
      if @sock_type == "nginx"
        @sock\sslhandshake false, nil, @ssl_verify
      else
        @sock\sslhandshake @ssl_verify, @luasec_opts
    elseif t == MSG_TYPE.error or @ssl_required
      @disconnect!
      nil, "the server does not support SSL connections"
    else
      true -- no SSL support, but not required by client

  send_message: (t, data, len) =>
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
    -- When this is called by encode_hstore, encode_json, etc., the default
    -- escape function is often used, making the self reference unavailable
    if val == nil or (self != nil and val == @NULL)
      return "NULL"

    switch type val
      when "number"
        return tostring val
      when "string"
        return "'#{(val\gsub "'", "''")}'"
      when "boolean"
        return val and "TRUE" or "FALSE"

    error "don't know how to escape value: #{val}"

  as_ident: (ident) =>
    return -> @escape_identifier ident

  as_array: (tbl) =>
    return (escape_literal) ->
      import encode_array from require "pgmoon.arrays"
      return encode_array tbl, escape_literal

  as_hstore: (tbl) =>
    return (escape_literal) ->
      import encode_hstore from require "pgmoon.hstore"
      return encode_hstore tbl, escape_literal

  as_json: (tbl) =>
    return (escape_literal) ->
      json = require "cjson"
      enc = json.encode tbl
      escape_literal enc

  __tostring: =>
    "<Postgres socket: #{@sock}>"

{ :Postgres, new: Postgres, :VERSION }

