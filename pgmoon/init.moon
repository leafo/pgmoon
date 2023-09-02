socket = require "pgmoon.socket"
import insert from table

import rshift, lshift, band, bxor from require "pgmoon.bit"

unpack = table.unpack or unpack

-- Protocol documentation:
-- https://www.postgresql.org/docs/current/protocol-message-formats.html

DEBUG = false
VERSION = "1.16.0"

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

-- frontend message types (sent)
MSG_TYPE_F = flipped {
  password: "p"

  query: "Q"

  parse: "P"
  bind: "B"
  describe: "D"
  execute: "E"
  close: "C"
  sync: "S"

  terminate: "X"
}

-- backend message types (recieved)
MSG_TYPE_B = flipped {
  auth: "R"
  parameter_status: "S"

  backend_key: "K"
  ready_for_query: "Z"

  parse_complete: "1"
  bind_complete: "2"
  close_complete: "3"

  row_description: "T"
  data_row: "D"

  command_complete: "C"

  error: "E"
  notice: "N"
  notification: "A"
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

-- maps pg_type.oid -> a name we can reference when converting the type to lua
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

  default_config: {
    application_name: "pgmoon"
    user: "postgres"
    host: "127.0.0.1"
    port: "5432"
    ssl: false
  }

  -- convert a lua value to pg_type.oid, string representation used for sending
  -- the value as a parameter in the extended query protocol
  -- select oid, typname, typcategory from pg_type;
  -- https://www.postgresql.org/docs/9.0/catalog-pg-type.html#CATALOG-TYPCATEGORY-TABLE
  type_serializers: {
    string: (v) =>
      25, v

    boolean: (v) =>
      16, v and "t" or "f"

    -- converts all numbers to numeric
    number: (v) =>
      1700, tostring v

    table: (v) =>
      if v_mt = getmetatable(v)
        if v_mt.pgmoon_serialize
          return v_mt.pgmoon_serialize v, @

      nil, "table does not implement pgmoon_serialize, can't serialize"
  }

  -- custom types supplementing PG_TYPES
  -- new ones can be added by using set_type_deserializer
  type_deserializers: {
    json: (val, name) =>
      import decode_json from require "pgmoon.json"
      decode_json val

    bytea: (val, name) =>
      @decode_bytea val

    array_boolean: (val, name) =>
      import decode_array from require "pgmoon.arrays"
      decode_array val, tobool, @

    array_number: (val, name) =>
      import decode_array from require "pgmoon.arrays"
      decode_array val, tonumber, @

    array_string: (val, name) =>
      import decode_array from require "pgmoon.arrays"
      decode_array val, nil, @

    array_json: (val, name) =>
      import decode_array from require "pgmoon.arrays"
      import decode_json from require "pgmoon.json"
      decode_array val, decode_json, @

    hstore: (val, name) =>
      import decode_hstore from require "pgmoon.hstore"
      decode_hstore val
  }

  -- this is the legacy method name, old undocumented api that someone might be using
  set_type_oid: (a,b) =>
    print "pgmoon: WARNING: set_type_oid is deprecated for set_type_deserializer"
    @set_type_deserializer a,b

  set_type_deserializer: (oid, name, deserializer) =>
    -- create a copy specific to this instance if we don't already have one
    unless rawget(@, "PG_TYPES")
      @PG_TYPES = {k,v for k,v in pairs @PG_TYPES}

    @PG_TYPES[assert tonumber oid] = name

    if deserializer
      unless rawget(@, "type_deserializers")
        @type_deserializers = {k,v for k,v in pairs @type_deserializers}

      @type_deserializers[name] = deserializer

  setup_hstore: =>
    res = unpack @query "SELECT oid FROM pg_type WHERE typname = 'hstore'"
    assert res, "hstore oid not found"
    @set_type_deserializer tonumber(res.oid), "hstore"

  -- config={}
  -- host: server hostname
  -- port: server port
  -- user: the username to authenticate with
  -- password: the username to authenticate with
  -- database: database to connect to
  -- application_name: name assigned to connection to server
  -- socket_type: type of socket to use (nginx, luasocket, cqueues)
  -- ssl: enable ssl connections
  -- ssl_verify: verify the certificate
  -- cqueues_openssl_context: manually created openssl.ssl.context for cqueues sockets
  -- luasec_opts: manually created options for LuaSocket ssl connections
  new: (@_config={}) =>

    -- NOTE: since config is a proxy table, we should avoid using it in hot code paths, like making queries
    @config = setmetatable {}, {
      __index: (t, key) ->
        value = @_config[key]
        if value == nil
          @default_config[key]
        else
          value
    }

    @convert_null = @config.convert_null
    @sock, @sock_type = socket.new @config.socket_type

  connect: =>
    connect_opts = switch @sock_type
      when "nginx"
        {
          pool: @config.pool_name or "#{@config.host}:#{@config.port}:#{@config.database}:#{@config.user}"
          pool_size: @config.pool_size
          backlog: @config.backlog
        }

    ok, err = @sock\connect @config.host, @config.port, connect_opts
    return nil, err unless ok

    if @sock\getreusedtimes! == 0
      if @config.ssl
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
    @send_message MSG_TYPE_F.terminate, {}
    @sock\close!

  keepalive: (...) =>
    @sock\setkeepalive ...

  -- see: http://25thandclement.com/~william/projects/luaossl.pdf
  create_cqueues_openssl_context: =>
    return unless @config.ssl_verify != nil or @config.cert or @config.key or @config.ssl_version

    ssl_context = require("openssl.ssl.context")

    out = ssl_context.new @config.ssl_version

    if @config.ssl_verify == true
      out\setVerify ssl_context.VERIFY_PEER

    if @config.ssl_verify == false
      out\setVerify ssl_context.VERIFY_NONE

    if @config.cert
      out\setCertificate @config.cert

    if @config.key
      out\setPrivateKey @config.key

    out

  create_luasec_opts: =>
    {
      key: @config.key
      certificate: @config.cert
      cafile: @config.cafile
      protocol: @config.ssl_version
      verify: @config.ssl_verify and "peer" or "none"
    }


  auth: =>
    t, msg = @receive_message!
    return nil, msg unless t

    unless MSG_TYPE_B.auth == t
      if MSG_TYPE_B.error == t
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
      when 10 -- AuthenticationSASL
        @scram_sha_256_auth msg
      else
        error "don't know how to auth: #{auth_type}"

  cleartext_auth: (msg) =>
    assert @config.password, "the database is requesting a password for authentication but you did not provide a password"

    @send_message MSG_TYPE_F.password, {
      @config.password
      NULL
    }

    @check_auth!

  -- https://www.postgresql.org/docs/current/sasl-authentication.html#SASL-SCRAM-SHA-256
  scram_sha_256_auth: (msg) =>
    assert @config.password, "the database is requesting a password for authentication but you did not provide a password"

    import random_bytes, x509_digest from require "pgmoon.crypto"

    -- '18' is the number set by postgres on the server side
    rand_bytes  = assert random_bytes 18

    import encode_base64 from require "pgmoon.util"

    c_nonce = encode_base64 rand_bytes
    nonce = "r=" .. c_nonce
    saslname = ""
    username = "n=" .. saslname
    client_first_message_bare = username .. "," .. nonce

    plus = false
    bare = false

    if msg\match "SCRAM%-SHA%-256%-PLUS"
      plus = true
    elseif msg\match "SCRAM%-SHA%-256"
      bare = true
    else
      error "unsupported SCRAM mechanism name: " .. tostring(msg)

    local gs2_cbind_flag
    local gs2_header
    local cbind_input
    local mechanism_name

    if bare
      gs2_cbind_flag = "n"
      gs2_header = gs2_cbind_flag .. ",,"
      cbind_input = gs2_header
      mechanism_name = "SCRAM-SHA-256" .. NULL
    elseif plus
      cb_name = "tls-server-end-point"
      gs2_cbind_flag = "p=" .. cb_name
      gs2_header = gs2_cbind_flag .. ",,"
      mechanism_name = "SCRAM-SHA-256-PLUS" .. NULL

      cbind_data = do
        if @sock_type == "cqueues"
          openssl_x509 = @sock\getpeercertificate!
          openssl_x509\digest "sha256", "s"
        else
          pem, signature = if @sock_type == "nginx"
            ssl = require("resty.openssl.ssl").from_socket(@sock)
            server_cert = ssl\get_peer_certificate()
            server_cert\to_PEM!, server_cert\get_signature_name!
          else
            server_cert = @sock\getpeercertificate()
            server_cert\pem!, server_cert\getsignaturename!

          signature = signature\lower!

          -- Handle the case when the signature is e.g. ECDSA-with-SHA384
          _, _, with_sig = signature\find("%-with%-(.*)")
          if with_sig
            signature = with_sig

          -- upgrade the signature if necessary (also handle the case of s/RSA-SHA1/sha256)
          if signature\match("^md5") or signature\match("^sha1") or signature\match("sha1$")
            signature = "sha256"

          assert x509_digest(pem, signature)

      cbind_input = gs2_header .. cbind_data

    client_first_message = gs2_header .. client_first_message_bare

    @send_message MSG_TYPE_F.password, {
      mechanism_name
      @encode_int #client_first_message
      client_first_message
    }

    t, msg = @receive_message()

    unless t
      return nil, msg

    server_first_message = msg\sub 5
    int32 = @decode_int msg, 4

    if int32 == nil or int32 != 11
      return nil, "server_first_message error: " .. msg

    channel_binding = "c=" .. encode_base64 cbind_input
    nonce = server_first_message\match "([^,]+)"

    unless nonce
      return nil, "malformed server message (nonce)"

    client_final_message_without_proof = channel_binding .. "," .. nonce

    xor = (a, b) ->
      result = for i=1,#a
        x = a\byte i
        y = b\byte i

        unless x and y
          return nil

        string.char bxor x, y

      table.concat result

    salt = server_first_message\match ",s=([^,]+)"

    unless salt
      return nil, "malformed server message (salt)"

    i = server_first_message\match ",i=(.+)"

    unless i
      return nil, "malformed server message (iteraton count)"

    if tonumber(i) < 4096
      return nil, "the iteration-count sent by the server is less than 4096"

    import kdf_derive_sha256, hmac_sha256, digest_sha256 from require "pgmoon.crypto"
    salted_password, err = kdf_derive_sha256 @config.password, salt, tonumber i

    unless salted_password
      return nil, err

    client_key, err = hmac_sha256 salted_password, "Client Key"

    unless client_key
      return nil, err

    stored_key, err = digest_sha256 client_key

    unless stored_key
      return nil, err

    auth_message = "#{client_first_message_bare },#{server_first_message },#{client_final_message_without_proof}"

    client_signature, err = hmac_sha256 stored_key, auth_message

    unless client_signature
      return nil, err

    proof = xor client_key, client_signature

    unless proof
      return nil, "failed to generate the client proof"

    client_final_message = "#{client_final_message_without_proof },p=#{encode_base64 proof}"

    @send_message MSG_TYPE_F.password, {
      client_final_message
    }

    t, msg = @receive_message()

    unless t
      return nil, msg

    server_key, err = hmac_sha256 salted_password, "Server Key"

    unless server_key
      return nil, err

    server_signature, err = hmac_sha256 server_key, auth_message

    unless server_signature
      return nil, err


    server_signature = encode_base64 server_signature
    sent_server_signature = msg\match "v=([^,]+)"

    if server_signature != sent_server_signature then
      return nil, "authentication exchange unsuccessful"

    @check_auth!

  md5_auth: (msg) =>
    import md5 from require "pgmoon.crypto"
    salt = msg\sub 5, 8
    assert @config.password, "missing password, required for connect"

    @send_message MSG_TYPE_F.password, {
      "md5"
      md5 md5(@config.password .. @config.user) .. salt
      NULL
    }

    @check_auth!

  check_auth: =>
    t, msg = @receive_message!
    return nil, msg unless t

    switch t
      when MSG_TYPE_B.error
        nil, @parse_error msg
      when MSG_TYPE_B.auth
        true
      else
        error "unknown response from auth"

  query: (q, ...) =>
    if select("#", ...) > 0
      @extended_query q, ...
    else
      @simple_query q


  -- query using the "simple" query protocol
  -- supports multiple queries, but no parameters
  simple_query: (q) =>
    if q\find NULL
      return nil, "invalid null byte in query"

    @send_message MSG_TYPE_F.query, {q, NULL}
    @receive_query_result!

  -- query using the "extended" query protocol
  -- supports only a single query, and parameters
  -- order of operations: Parse, Bind, portal Describe, Execute, Close, Sync
  -- NOTE: due to the additional steps, this protocol comes with a performance penalty
  extended_query: (q, ...) =>
    if q\find NULL
      return nil, "invalid null byte in query"

    num_params = select "#", ...

    parse_data = {
      NULL -- empty string, store query in unnamed prepared statement
      q, NULL
      @encode_int(num_params, 2) -- parameter type OIDs will follow
    }

    bind_data = {
      NULL -- empty string, destination is unamed portal
      NULL -- empty string, source is unamed statement

      @encode_int(0, 2) -- number of parameter format codes, 0 to default to all text
      @encode_int(num_params, 2) -- parameter values follow
    }

    for idx=1,num_params
      v = select idx, ...

      if v == @NULL or v == nil
        insert parse_data, @encode_int 0 -- OID is unspecified for NULL special case
        insert bind_data, @encode_int -1

      else
        v_type = type v

        type_oid, value_bytes = if fn = @type_serializers[v_type]
          _oid, _value_or_err, _third = fn @, v
          if _oid == nil
            full_error = "pgmoon: param #{idx}: #{_value_or_err or "failed to serialize type: #{v_type}"}"
            return nil, full_error

          if _third != nil
            return nil, "pgmoon: param #{idx}: please do not return a third value from serializer function, we may use this value in the future for binary formats"

          _oid, _value_or_err
        else
          0, "#{v}"

        insert parse_data, @encode_int type_oid
        insert bind_data, @encode_int #value_bytes
        insert bind_data, value_bytes


    insert bind_data, @encode_int 0, 2 -- number of result format codes, 0 to default to all text

    @send_messages {
      { MSG_TYPE_F.parse, parse_data }
      { MSG_TYPE_F.bind, bind_data }

      {
         MSG_TYPE_F.describe, {
          "P" -- describe a portal
          NULL -- empty string, use the unnamed portal
        }
      }

      {
        MSG_TYPE_F.execute, {
          NULL -- empty string, use unamed portal
          @encode_int(0) -- 0, do not limit number of returned rows
        }
      }

      {
        MSG_TYPE_F.close, {
          "P" -- close a portal
          NULL -- empty string, close unnamed portal
        }
      }

      {
        MSG_TYPE_F.sync, { }
      }
    }

    @receive_query_result!

  -- NOTE: this is called for both the simple query and the extended query protocol
  receive_query_result: =>
    local row_desc, data_rows, command_complete, err_msg

    local result, notifications, notices
    num_queries = 0

    while true
      t, msg = @receive_message!
      return nil, msg unless t
      switch t
        when MSG_TYPE_B.data_row
          data_rows = {} unless data_rows
          insert data_rows, msg
        when MSG_TYPE_B.row_description
          row_desc = msg
        when MSG_TYPE_B.error
          err_msg = msg
        when MSG_TYPE_B.notice
          notices = {} unless notices
          -- a notice is encoded the same as an error, but does not mean we should abort with failure
          insert notices, (@parse_error(msg))
        when MSG_TYPE_B.command_complete
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
        when MSG_TYPE_B.ready_for_query
          break
        when MSG_TYPE_B.notification
          notifications = {} unless notifications
          insert notifications, @parse_notification(msg)
        -- these responsees only come from the extended query protocol
        when MSG_TYPE_B.parse_complete, MSG_TYPE_B.bind_complete, MSG_TYPE_B.close_complete
          nil
        else
          if DEBUG
            print "Unhandled message in query result: #{t}"

    if err_msg
      return nil, @parse_error(err_msg), result, num_queries, notifications, notices

    result, num_queries, notifications, notices

  wait_for_notification: =>
    while true
      t, msg = @receive_message!
      return nil, msg unless t
      switch t
        when MSG_TYPE_B.notification
          return @parse_notification(msg)

  format_query_result: (row_desc, data_rows, command_complete) =>
    local command, affected_rows

    if command_complete
      command = command_complete\match "^%w+"
      affected_rows = tonumber command_complete\match "(%d+)%z$"

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

      if len < 0 or len == 4294967295
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

      if MSG_TYPE_B.error == t
        return nil, @parse_error(msg)

      break if MSG_TYPE_B.ready_for_query == t

    true

  -- NOTE: timeout of 0 would cause this clinet to disconnect if it's not ready
  receive_message: =>
    prefix, err = @sock\receive 5

    unless prefix
      return nil, "receive_message: failed to get type: #{err}"

    t = prefix\sub 1,1
    len = prefix\sub 2

    len = @decode_int len
    len -= 4
    msg = @sock\receive len
    t, msg

  send_startup_message: =>
    assert @config.user, "missing user for connect"
    assert @config.database, "missing database for connect"

    data = {
      @encode_int 196608
      "user", NULL
      @config.user, NULL
      "database", NULL
      @config.database, NULL
      "application_name", NULL
      @config.application_name, NULL
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

    if t == MSG_TYPE_B.parameter_status
      switch @sock_type
        when "nginx"
          @sock\sslhandshake false, nil, @config.ssl_verify
        when "luasocket"
          @sock\sslhandshake @config.luasec_opts or @create_luasec_opts!
        when "cqueues"
          @sock\starttls @config.cqueues_openssl_context or @create_cqueues_openssl_context!
        else
          error "don't know how to do ssl handshake for socket type: #{@sock_type}"
    elseif t == MSG_TYPE_B.error or @config.ssl_required
      nil, "the server does not support SSL connections"
    else
      true -- no SSL support, but not required by client

  -- send multiple messages all together. There is a substantial overhead from
  -- sending messages one at a time, so this should be used if we can safely
  -- bulk together multiple messages
  -- format { { message_type, message_data}, ...  }
  send_messages: (messages) =>
    data = for {message_type, message_data} in *messages
      len = _len message_data
      len += 4 -- includes the length of the length integer
      {
        message_type
        @encode_int len
        message_data

      }

    @sock\send data


  send_message: (t, data, len) =>
    len = _len data if len == nil
    len += 4 -- includes the length of the length integer

    @sock\send {
      t
      @encode_int len
      data
    }

  decode_int: (str, bytes=#str) =>
    -- make decoding common case 0 faster
    switch str
      when "\0\0", "\0\0\0\0"
        return 0

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
    -- make sending 0 faster
    if n == 0
      if bytes == 2
        return "\0\0"
      if bytes == 4
        return "\0\0\0\0"

    switch bytes
      when 4
        a = band n, 0xff
        b = band rshift(n, 8), 0xff
        c = band rshift(n, 16), 0xff
        d = band rshift(n, 24), 0xff
        string.char d, c, b, a
      when 2
        a = band n, 0xff
        b = band rshift(n, 8), 0xff
        string.char b, a
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
    if val == (@ and @NULL or Postgres.NULL)
      return "NULL"

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

