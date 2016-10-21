
-- make luasockets send behave like openresty's
__flatten = (t, buffer) ->
  switch type(t)
    when "string"
      buffer[#buffer + 1] = t
    when "table"
      for thing in *t
        __flatten thing, buffer


_flatten = (t) ->
  buffer = {}
  __flatten t, buffer
  table.concat buffer

class CqueuesSocket
  connect: (host, port, opts) =>
    socket = require "cqueues.socket"
    errno = require "cqueues.errno"

    @sock = socket.connect {
      :host
      :port
    }

    if @timeout
      @sock\settimeout @timeout

    @sock\setmode "bn", "bn"
    success, err =  @sock\connect!
    unless success
      return nil, errno.strerror(err)

    true

  sslhandshake: =>
    @sock\starttls!

  send: (...) =>
    @sock\write _flatten ...

  receive: (...) =>
    @sock\read ...

  close: =>
    @sock\close!

  settimeout: (t) =>
    if t
      t = t/1000

    if @sock
      @sock\settimeout t
    else
      @timeout = t

  -- openresty pooling interface, disable pooling
  getreusedtimes: => 0

new = ->
  CqueuesSocket!, "cqueues"

{ :new , :CqueuesSocket }


