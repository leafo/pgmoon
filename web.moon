lapis = require "lapis"

class Postgres
  AUTH_REQ_OK = 0
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
    @sock = ngx.socket.tcp!
    ok, err = @sock\connect @host, tonumber @port
    return nil, err unless ok
    print "startup:", @send_startup_message!

    while true
      t, msg = @receive_message!
      print t, msg

  receive_message: =>
    t, err = @sock\receive 1
    return nil, "failed to get type: #{err}" unless t
    len, err = @sock\receive 4
    return nil, "failed to get len: #{err}" unless len
    len = @decode_int len
    len -= 4
    msg = @sock\receive len
    t\byte!, msg

  send_startup_message: =>
    data = {
      @encode_int 196608
      "user", NULL
      @user, NULL
      "database", NULL
      @db, NULL
      NULL
    }

    print "Sending #{_len data} bytes"

    @sock\send {
      @encode_int _len(data) + 4
      data
    }

  send_message: (t, data, len=nil) =>
    len = _len len if len == nil
    len += 4 -- includes the length of the length integer

    @sock\send {
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


lapis.serve class extends lapis.Application
  "/": =>
    p = Postgres "127.0.0.1", "5432", "postgres", "moonrocks"

    @html ->
      text ":"
      pre require("moon").dump {
        p\connect!
      }


