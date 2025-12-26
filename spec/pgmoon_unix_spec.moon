import Postgres from require "pgmoon"

SOCKET_PATH = "/var/run/postgresql/.s.PGSQL.5432"

-- Basic test to verify Unix socket support loads correctly
describe "Unix socket support", ->
  it "should choose nginx or luaposix when socket_path is provided", ->
    pg = Postgres {
      socket_path: "/tmp/test.sock"
      user: "postgres"
      database: "test"
    }

    if ngx and ngx.get_phase! != "init"
      assert.equal "nginx", pg.sock_type
    else
      assert.equal "luaposix", pg.sock_type

  it "should accept socket_path in configuration", ->
    pg = Postgres {
      socket_path: SOCKET_PATH
      user: "postgres"
      database: "test"
    }

    assert.equal SOCKET_PATH, pg.config.socket_path

  it "should default to luasocket when no socket_path is provided", ->
    pg = Postgres {
      user: "postgres"
      database: "test"
    }

    -- Should not be luaposix since no socket_path provided
    assert.is_not.equal "luaposix", pg.sock_type

  it "should have socket_path as nil in default config", ->
    pg = Postgres {}
    assert.is_nil pg.config.socket_path

  it "should override socket_type when socket_path is provided", ->
    -- Even if we explicitly set socket_type to something else,
    -- providing socket_path should force luaposix
    pg = Postgres {
      socket_type: "luasocket"
      socket_path: "/tmp/test.sock"
      user: "postgres"
      database: "test"
    }

    if ngx and ngx.get_phase! != "init"
      assert.equal "nginx", pg.sock_type
    else
      assert.equal "luaposix", pg.sock_type

  -- This test would require an actual Unix socket PostgreSQL server
  -- Keeping it commented out for now
  it "should connect via Unix socket", ->
    pg = Postgres {
      socket_path: SOCKET_PATH
      user: "postgres"
      database: "postgres"
    }

    success, err = pg\connect!
    assert success, "Failed to connect: #{err}"

    result, err = pg\query "SELECT 1 as test"
    assert result, "Failed to query: #{err}"
    assert.equal 1, result[1].test

    pg\disconnect!
