
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
  }

  NULL = "\0"

  import rshift, lshift, band from require "bit"

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

  new: (@host, @port, @user, @db) =>

  connect: =>
    @sock = socket.tcp!
    ok, err = @sock\connect @host, tonumber @port
    return nil, err unless ok
    success, err = @send_startup_message!
    return nil, err unless success

    @auth!
    @wait_until_ready!

    print "Looping"
    while true
      t, msg = @receive_message!
      msg = msg\gsub "%z", " ** "
      print t, "`#{msg}`"

  auth: =>
    t, msg = @receive_message!
    if TYPE.auth_ok == t
      return true

    error "don't know how to auth #{t}"

  wait_until_ready: =>
    while true
      t = @receive_message!
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
    len = _len len if len == nil
    len += 4 -- includes the length of the length integer

    @sock\send _flatten {
      t
      @encode_int len
      data
    }

  decode_int: (str, bytes=4) =>
    switch bytes
      when 4
        d, c, b, a = str\byte 1, 4
        a + lshift(b, 8) + lshift(c, 16) + lshift(d, 24)
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




{ :Postgres }

