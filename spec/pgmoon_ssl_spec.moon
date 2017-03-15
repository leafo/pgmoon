import Postgres from require "pgmoon"

HOST = "127.0.0.1"
PORT = "9999"
USER = "postgres"
DB = "pgmoon_test"

describe "pgmoon with server", ->
  local pg

  setup ->
    os.execute "spec/postgres.sh start"

  teardown ->
    os.execute "spec/postgres.sh stop"

  it "connects without ssl on ssl server", ->
    pg = Postgres {
      database: DB
      port: PORT
      user: USER
      host: HOST
    }
    assert pg\connect!
    assert pg\query "select * from information_schema.tables"
    pg\disconnect!

  it "connects with ssl on ssl server (defaults to TLS v1.0)", ->
    pg = Postgres {
      database: DB
      port: PORT
      user: USER
      host: HOST
      ssl: true
      ssl_required: true
    }

    assert pg\connect!
    assert pg\query "select * from information_schema.tables"
    pg\disconnect!

  it "connects with TLS v1.0 on ssl server", ->
    pg = Postgres {
      database: DB
      port: PORT
      user: USER
      host: HOST
      ssl: true
      ssl_required: true
      ssl_version: "tlsv1"
    }

    assert pg\connect!
    assert pg\query "select * from information_schema.tables"
    pg\disconnect!

  it "connects with TLS v1.2 on ssl server", ->
    pg = Postgres {
      database: DB
      port: PORT
      user: USER
      host: HOST
      ssl: true
      ssl_required: true
      ssl_version: "tlsv1_2"
    }

    assert pg\connect!
    assert pg\query "select * from information_schema.tables"
    pg\disconnect!


