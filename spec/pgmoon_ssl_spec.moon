import Postgres from require "pgmoon"

import psql, HOST, PORT, USER, PASSWORD, DB from require "spec.util"

describe "pgmoon with server", ->
  local pg

  setup ->
    os.execute "spec/postgres.sh start ssl"

    r = { psql "drop database if exists #{DB}" }
    assert 0 == r[#r], "failed to execute psql: drop database"

    r = { psql "create database #{DB}" }
    assert 0 == r[#r], "failed to execute psql: create database"

  teardown ->
    os.execute "spec/postgres.sh stop"

  describe "nginx", ->
    unless ngx
      it "(disabled)", -> pending "Skipping nginx tests, no ngx global available"
      return

    it "connects with ssl", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        socket_type: "nginx"
      }

      assert pg\connect!
      assert pg\query "select * from information_schema.tables"

      pg\disconnect!


  describe "luasocket", ->
    if ngx
      it "(disabled)", -> pending "skipping luasocket in nginx testing mode"
      return

    it "connects without ssl on ssl server", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        socket_type: "luasocket"
      }
      assert pg\connect!
      assert pg\query "select * from information_schema.tables"
      pg\disconnect!

    it "connects with ssl on ssl server (defaults to highest available, TLSv1.3)", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        ssl_required: true
        socket_type: "luasocket"
      }

      assert pg\connect!
      res = assert pg\query [[SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid()]]
      assert.same 'TLSv1.3', res[1].version
      pg\disconnect!

    it "connects with TLSv1.2 on ssl server", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        ssl_required: true
        ssl_version: "tlsv1_2"
        socket_type: "luasocket"
      }

      assert pg\connect!
      res = assert pg\query [[SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid()]]
      assert.same 'TLSv1.2', res[1].version
      pg\disconnect!

    it "connects with TLSv1.3 on ssl server", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        ssl_required: true
        ssl_version: "tlsv1_3"
        socket_type: "luasocket"
      }

      assert pg\connect!
      res = assert pg\query [[SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid()]]
      assert.same 'TLSv1.3', res[1].version
      pg\disconnect!

  describe "cqueues", ->
    if ngx
      it "(disabled)", -> pending "skipping cqueues in nginx testing mode"
      return

    it "connects with ssl", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        socket_type: "cqueues"
      }

      assert pg\connect!
      assert pg\query "select * from information_schema.tables"

      pg\disconnect!


    it "connects with ssl with context options", ->
      pg = Postgres {
        database: DB
        port: PORT
        user: USER
        password: PASSWORD
        host: HOST
        ssl: true
        socket_type: "cqueues"
        ssl_version: "TLSv1_2"
      }

      assert pg\connect!
      assert pg\query "select * from information_schema.tables"

      res = assert pg\query [[SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid()]]
      assert.same 'TLSv1.2', res[1].version

      pg\disconnect!

