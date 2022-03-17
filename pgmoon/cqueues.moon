
import flatten from require "pgmoon.util"

-- socket proxy class to make cqueues socket behave like ngx.socket.tcp
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

  -- args: [context][, timeout]
  starttls: (...) =>
    @sock\starttls ...

  -- returns openssl.x509 object
  getpeercertificate: =>
    ssl = assert @sock\checktls!
    assert ssl\getPeerCertificate!, "no peer certificate available"

  send: (...) =>
    @sock\write flatten ...

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

  -- openresty pooling interface, always return 0 to suggest that the socket
  -- is connecting for the first time
  getreusedtimes: => 0

  setkeepalive: =>
    error "You attempted to call setkeepalive on a cqueues.socket. This method is only available for the ngx cosocket API for connection pooling"

{ :CqueuesSocket }


