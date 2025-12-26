import PostgresPool from require "pgmoon.pool"
import HOST, PORT, USER, PASSWORD, DB, psql from require "spec.util"

describe "pgmoon.pool", ->
  setup ->
    os.execute "spec/postgres.sh start"

  teardown ->
    os.execute "spec/postgres.sh stop"

  local pool

  setup ->
    r = { psql "drop database if exists #{DB}" }
    assert 0 == r[#r], "failed to execute psql: drop database"

    r = { psql "create database #{DB}" }
    assert 0 == r[#r], "failed to execute psql: create database"

  describe "connection lifecycle", ->
    after_each ->
      pool\disconnect! if pool

    it "connects and creates first instance", ->
      pool = PostgresPool { database: DB, user: USER, password: PASSWORD, host: HOST, port: PORT }
      assert pool\connect!
      assert.same 1, pool\pool_size!

    it "fails to connect with invalid config", ->
      pool = PostgresPool { database: "nonexistent_db_xyz", user: USER, password: PASSWORD, host: HOST, port: PORT }
      res, err = pool\connect!
      assert.is_nil res
      assert.truthy err

    it "returns error if already connected", ->
      pool = PostgresPool { database: DB, user: USER, password: PASSWORD, host: HOST, port: PORT }
      assert pool\connect!
      res, err = pool\connect!
      assert.is_nil res
      assert.same "already connected", err

    it "disconnects all connections", ->
      pool = PostgresPool { database: DB, user: USER, password: PASSWORD, host: HOST, port: PORT }
      assert pool\connect!
      assert pool\query "select 1"
      assert pool\disconnect!
      assert.same 0, pool\pool_size!

    it "returns error when querying without connect", ->
      pool = PostgresPool { database: DB, user: USER, password: PASSWORD, host: HOST, port: PORT }
      res, err = pool\query "select 1"
      assert.is_nil res
      assert.same "not connected", err

  describe "pool growth", ->
    before_each ->
      pool = PostgresPool { database: DB, user: USER, password: PASSWORD, host: HOST, port: PORT }
      assert pool\connect!

    after_each ->
      pool\disconnect!

    it "reuses connection when not busy", ->
      assert pool\query "select 1"
      assert pool\query "select 2"
      assert.same 1, pool\pool_size!

    it "creates new connection when current is busy", ->
      pg1 = pool.pool[1]
      pg1.busy = true

      assert pool\query "select 1"
      assert.same 2, pool\pool_size!

      pg1.busy = false

    it "tracks active connections correctly", ->
      assert.same 0, pool\active_connections!

      pg1 = pool.pool[1]
      pg1.busy = true
      assert.same 1, pool\active_connections!

      pg1.busy = false
      assert.same 0, pool\active_connections!

  describe "max_pool_size", ->
    after_each ->
      pool\disconnect! if pool

    it "respects max_pool_size limit", ->
      pool = PostgresPool {
        database: DB, user: USER, password: PASSWORD, host: HOST, port: PORT
        max_pool_size: 2
      }
      assert pool\connect!

      pool.pool[1].busy = true

      assert pool\query "select 1"
      assert.same 2, pool\pool_size!

      pool.pool[2].busy = true

      res, err = pool\query "select 1"
      assert.is_nil res
      assert.same "pool exhausted, max_pool_size reached", err

      pool.pool[1].busy = false
      pool.pool[2].busy = false

    it "allows unlimited growth without max_pool_size", ->
      pool = PostgresPool { database: DB, user: USER, password: PASSWORD, host: HOST, port: PORT }
      assert pool\connect!

      for i = 1, 5
        for pg in *pool.pool
          pg.busy = true
        assert pool\query "select 1"

      assert.same 6, pool\pool_size!

      for pg in *pool.pool
        pg.busy = false

  describe "settings propagation", ->
    before_each ->
      pool = PostgresPool { database: DB, user: USER, password: PASSWORD, host: HOST, port: PORT }
      assert pool\connect!

    after_each ->
      pool\disconnect!

    it "propagates settimeout to existing connections", ->
      pool\settimeout 5000
      assert.same 5000, pool._timeout

    it "propagates settimeout to new connections", ->
      pool\settimeout 5000

      pool.pool[1].busy = true
      assert pool\query "select 1"
      pool.pool[1].busy = false

      assert.same 2, pool\pool_size!

    it "shares PG_TYPES table across all connections", ->
      pool\set_type_deserializer 25, "my_text", (val) -> val

      -- Force new connection
      pool.pool[1].busy = true
      assert pool\query "select 'test'::text"
      pool.pool[1].busy = false

      -- All connections should share the same PG_TYPES table
      assert.same 2, pool\pool_size!
      assert.same pool.PG_TYPES, pool.pool[1].PG_TYPES
      assert.same pool.PG_TYPES, pool.pool[2].PG_TYPES
      -- Verify the custom type is registered
      assert.same "my_text", pool.PG_TYPES[25]

  describe "query methods", ->
    before_each ->
      pool = PostgresPool { database: DB, user: USER, password: PASSWORD, host: HOST, port: PORT }
      assert pool\connect!

    after_each ->
      pool\disconnect!

    it "executes simple query", ->
      res = assert pool\query "select 1 as num"
      assert.same { { num: 1 } }, res

    it "executes extended query with params", ->
      res = assert pool\extended_query "select $1::int as num", 42
      assert.same { { num: 42 } }, res

    it "executes simple_query directly", ->
      res = assert pool\simple_query "select 1 as num"
      assert.same { { num: 1 } }, res

    it "errors on wait_for_notification", ->
      assert.has_error (-> pool\wait_for_notification!), "can't use wait for notification with pool"

  describe "static methods", ->
    it "escape_identifier works without connection", ->
      pool = PostgresPool {}
      assert.same '"my_table"', pool\escape_identifier "my_table"

    it "escape_literal works without connection", ->
      pool = PostgresPool {}
      assert.same "'hello'", pool\escape_literal "hello"

    it "has NULL constant", ->
      pool = PostgresPool {}
      assert.truthy pool.NULL
