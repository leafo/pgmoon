import Postgres from require "pgmoon"

import psql_unix, SOCKET_PATH, USER, PASSWORD, DB from require "spec.util"

describe "pgmoon Unix socket with server", ->
  setup ->
    os.execute "spec/postgres.sh start unix"

    r = { psql_unix "drop database if exists #{DB}" }
    assert 0 == r[#r], "failed to execute psql_unix: drop database"

    r = { psql_unix "create database #{DB}" }
    assert 0 == r[#r], "failed to execute psql_unix: create database"

  teardown ->
    os.execute "spec/postgres.sh stop"

  -- Test that socket_path configuration selects the right socket type
  describe "socket type selection", ->
    it "should choose luaposix when socket_path is provided outside nginx", ->
      unless ngx
        pg = Postgres {
          socket_path: "/tmp/test.sock"
          user: "postgres"
          database: "test"
        }
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

  -- Actual connection tests via Unix socket
  describe "luaposix socket", ->
    local pg

    before_each ->
      pg = Postgres {
        socket_path: SOCKET_PATH
        user: USER
        password: PASSWORD
        database: DB
      }

    after_each ->
      pg\disconnect! if pg

    it "connects via Unix socket", ->
      success, err = pg\connect!
      assert success, "Failed to connect: #{err}"

      result, err = pg\query "SELECT 1 as test"
      assert result, "Failed to query: #{err}"
      assert.same { { test: 1 } }, result

    it "creates and queries table", ->
      assert pg\connect!

      res = assert pg\query [[
        create table unix_test (
          id serial not null,
          name text,
          primary key (id)
        )
      ]]
      assert.same true, res

      res = assert pg\query [[
        insert into unix_test (name) values ('hello') returning id, name
      ]]
      assert.same {
        affected_rows: 1
        { id: 1, name: "hello" }
      }, res

      res = assert pg\query [[
        select * from unix_test
      ]]
      assert.same {
        { id: 1, name: "hello" }
      }, res

      assert pg\query [[drop table unix_test]]

    it "handles errors correctly", ->
      assert pg\connect!

      status, err = pg\query "select * from nonexistent_table"
      assert.falsy status
      assert.truthy err\match "does not exist"

    it "can reconnect after disconnect", ->
      do return pending "luaposix socket does not support reconnect on same instance"
      assert pg\connect!
      assert pg\query "select 1"
      pg\disconnect!

      assert pg\connect!
      assert pg\query "select 1"
