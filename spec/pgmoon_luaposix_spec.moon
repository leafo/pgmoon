describe "pgmoon luaposix unix sockets", ->
  import Postgres from require "pgmoon"
  import socket_path_for from require "pgmoon.posix_socket"

  ensure_environment = ->
    ok_socket, socket_mod = pcall -> require "posix.sys.socket"
    unless ok_socket
      return nil, "luaposix integration tests require posix.sys.socket: #{socket_mod}"

    unless socket_mod and socket_mod.AF_UNIX and type(socket_mod.socket) == "function" and type(socket_mod.connect) == "function"
      return nil, "posix.sys.socket is missing UNIX domain socket support (AF_UNIX)"

    ok_stat, stat_mod = pcall -> require "posix.sys.stat"
    unless ok_stat
      return nil, "luaposix integration tests require posix.sys.stat: #{stat_mod}"

    socket_dir = os.getenv("PGMOON_LUAPOSIX_SOCKET_DIR") or "/var/run/postgresql"
    unless socket_dir and socket_dir != ""
      return nil, "set PGMOON_LUAPOSIX_SOCKET_DIR to the directory containing the postgres socket"

    dir_attr, dir_err = stat_mod.stat socket_dir
    unless dir_attr
      return nil, "postgres socket directory not available: #{socket_dir} (#{dir_err})"

    port_str = os.getenv("PGMOON_LUAPOSIX_PORT")
    port = tonumber(port_str) or 5432

    socket_path = socket_path_for socket_dir, port
    path_attr, path_err = stat_mod.stat socket_path
    unless path_attr
      return nil, "postgres unix socket not found at #{socket_path} (#{path_err})"

    user = os.getenv("PGMOON_LUAPOSIX_USER") or "postgres"
    database = os.getenv("PGMOON_LUAPOSIX_DB") or "postgres"
    password = os.getenv("PGMOON_LUAPOSIX_PASSWORD")

    {
      :socket_dir
      :socket_path
      :port
      :user
      :database
      :password
    }

  build_options = (config, host, port) ->
    opts = {
      :host
      database: config.database
      socket_type: "luaposix"
    }

    if port
      opts.port = port

    if config.user
      opts.user = config.user

    if config.password and config.password != ""
      opts.password = config.password

    opts

  connect_or_pending = (pg, config, context) ->
    ok, err = pg\connect!
    unless ok
      if err
        if err\match "role" and err\match "does not exist"
          return pending "luaposix integration requires a PostgreSQL role. Set PGMOON_LUAPOSIX_USER to an existing role (current: #{config.user or 'postgres'})."
        if err\match "password authentication failed"
          return pending "luaposix integration requires PostgreSQL credentials. Provide PGMOON_LUAPOSIX_USER and PGMOON_LUAPOSIX_PASSWORD."
      assert.truthy ok, "failed to connect #{context}: #{err}"
    true

  it "connects using a unix socket directory", ->
    config, reason = ensure_environment!
    unless config
      return pending reason or "luaposix socket integration prerequisites not satisfied"

    opts = build_options config, config.socket_dir, config.port
    pg = Postgres opts

    connect_or_pending pg, config, "via socket directory"

    res = assert pg\query "select 1 as one"
    assert.same {{ one: 1 }}, res

    assert.truthy pg\disconnect!

  it "connects using an explicit unix socket path", ->
    config, reason = ensure_environment!
    unless config
      return pending reason or "luaposix socket integration prerequisites not satisfied"

    opts = build_options config, config.socket_path
    pg = Postgres opts

    connect_or_pending pg, config, "via socket path"

    res = assert pg\query "select 42 as answer"
    assert.same {{ answer: 42 }}, res

    assert.truthy pg\disconnect!
