lapis = require "lapis"

class Postgres
  AUTH_REQ_OK = 0

  import rshift, lshift, band from require "bit"

  new: (@host, @port, @db) =>

  connect: =>
    @sock = ngx.socket.tcp!
    ok, err = @sock\connect @host, tonumber @port
    return nil, err unless ok
    msg = "R#{@encode_int AUTH_REQ_OK}"

  receive_message: =>
    t, err = @sock\receive 1
    return nil, "failed to get type: #{err}" unless t
    len, err = @sock\receive 4
    return nil, "failed to get len: #{err}" unless len
    len = @decode_int len

  send_message: (t, data, len=#data) =>
    @sock\send t .. @encode_int(len) .. data

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
    p = Postgres "127.0.0.1", "5432", "moonrocks"

    @html ->
      text ":"
      pre require("moon").dump {
        -- p\connect!
      }


