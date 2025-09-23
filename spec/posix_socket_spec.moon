describe "posix socket", ->
  PosixSocket = nil
  socket_path_for = nil
  env = nil
  module = nil

  before_each ->
    env = {
      connect_calls: {}
      poll_calls: {}
      write_calls: {}
      write_returns: {}
      read_queue: {}
    }

    stub_socket = {
      AF_UNIX: "AF_UNIX"
      SOCK_STREAM: "SOCK_STREAM"
      socket: -> 42
      connect: (fd, addr) ->
        table.insert env.connect_calls, { fd: fd, addr: addr }
        true
    }

    stub_unistd = {
      close: -> env.closed = true
      write: (fd, data) ->
        table.insert env.write_calls, data
        if #env.write_returns > 0
          return table.remove env.write_returns, 1
        #data
      read: (fd, len) ->
        if #env.read_queue > 0
          return table.remove env.read_queue, 1
        string.rep "r", len
    }

    stub_errno = {
      strerror: (code) -> "err#{code or ''}"
      errno: -> 0
      EINTR: 4
      EAGAIN: 11
      EWOULDBLOCK: 11
    }

    stub_poll = {
      POLLIN: 1
      POLLOUT: 4
      poll: (fds, timeout) ->
        table.insert env.poll_calls, { events: fds[1].events, timeout: timeout }
        1
    }

    package.loaded["posix.sys.socket"] = stub_socket
    package.loaded["posix.unistd"] = stub_unistd
    package.loaded["posix.errno"] = stub_errno
    package.loaded["posix.poll"] = stub_poll
    package.loaded["pgmoon.posix_socket"] = nil

    module = require "pgmoon.posix_socket"
    PosixSocket = module.PosixSocket
    socket_path_for = module.socket_path_for

    env.stub_poll = stub_poll
    env.stub_unistd = stub_unistd

  after_each ->
    for name in *{"posix.sys.socket", "posix.unistd", "posix.errno", "posix.poll", "pgmoon.posix_socket"}
      package.loaded[name] = nil

  it "builds default postgres socket path from a directory", ->
    assert.same "/tmp/.s.PGSQL.5432", socket_path_for "/tmp", 5432
    assert.same "/tmp/.s.PGSQL.5432", socket_path_for "/tmp/", nil
    assert.same "/custom/.s.PGSQL.7000", socket_path_for "/custom", 7000

  it "connects using a computed unix socket path", ->
    sock = PosixSocket!
    ok, err = sock\connect "/var/run/postgresql", 5432
    assert.truthy ok
    assert.is_nil err
    assert.same {{ fd: 42, addr: { family: "AF_UNIX", path: "/var/run/postgresql/.s.PGSQL.5432" } }}, env.connect_calls

  it "sends flattened payloads over the socket", ->
    sock = PosixSocket!
    sock\connect "/tmp", 5432
    bytes = sock\send {"a", "b", "c"}
    assert.same {"abc"}, env.write_calls
    assert.equal 3, bytes

  it "reads until the requested length is satisfied", ->
    table.insert env.read_queue, "ab"
    table.insert env.read_queue, "cd"

    sock = PosixSocket!
    sock\connect "/tmp", 5432
    data, err = sock\receive 4
    assert.is_nil err
    assert.equal "abcd", data

  it "uses poll when a timeout is configured", ->
    sock = PosixSocket!
    sock\settimeout 25
    sock\connect "/tmp", 5432
    sock\send "payload"

    assert.same {{ events: env.stub_poll.POLLOUT, timeout: 25 }}, env.poll_calls

  it "returns timeout errors from poll", ->
    env.stub_poll.poll = (fds, timeout) ->
      table.insert env.poll_calls, { events: fds[1].events, timeout: timeout }
      0

    sock = PosixSocket!
    sock\settimeout 10
    sock\connect "/tmp", 5432
    data, err = sock\receive 4
    assert.is_nil data
    assert.equal "timeout", err
