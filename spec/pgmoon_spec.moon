
import Postgres from require "pgmoon"

HOST = "127.0.0.1"
USER = "postgres"
DB = "pgmoon_test"

describe "pgmoon with server", ->
  local pg

  setup ->
    os.execute "dropdb --if-exists -U '#{USER}' '#{DB}'"
    os.execute "createdb -U postgres '#{DB}'"

    pg = Postgres {
      database: DB
      user: USER
      host: HOST
    }
    assert pg\connect!

  it "should create and drop table", ->
    res = assert pg\query [[
      create table hello_world (
        id serial not null,
        name text,
        count integer not null default 0,
        primary key (id)
      )
    ]]

    assert.same true, res

    res = assert pg\query [[
      drop table hello_world
    ]]

    assert.same true, res

  describe "with table", ->
    before_each ->
      assert pg\query [[
        create table hello_world (
          id serial not null,
          name text,
          count integer not null default 0,
          flag boolean default TRUE,

          primary key (id)
        )
      ]]

    after_each ->
      assert pg\query [[
        drop table hello_world
      ]]

    it "should insert a row", ->
      res = assert pg\query [[
        insert into "hello_world" ("name", "count") values ('hi', 100)
      ]]

      assert.same { affected_rows: 1 }, res

    it "should insert a row with return value", ->
      res = assert pg\query [[
        insert into "hello_world" ("name", "count") values ('hi', 100) returning "id"
      ]]

      assert.same {
        affected_rows: 1
        { id: 1 }
      }, res

    it "should select from empty table", ->
      res = assert pg\query [[select * from hello_world limit 2]]
      assert.same {}, res

    it "should delete nothing", ->
      res = assert pg\query [[delete from hello_world]]
      assert.same { affected_rows: 0 }, res

    it "should update no rows", ->
      res = assert pg\query [[update "hello_world" SET "name" = 'blahblah']]
      assert.same { affected_rows: 0 }, res

    describe "with rows", ->
      before_each ->
        for i=1,10
          assert pg\query [[
            insert into "hello_world" ("name", "count")
              values (']] .. "thing_#{i}" .. [[', ]] .. i .. [[)
          ]]

      it "should select some rows", ->
        res = assert pg\query [[ select * from hello_world ]]
        assert.same "table", type(res)
        assert.same 10, #res


      it "should update rows", ->
        res = assert pg\query [[
          update "hello_world" SET "name" = 'blahblah'
        ]]

        assert.same { affected_rows: 10 }, res
        assert.same "blahblah",
          unpack(pg\query "select name from hello_world limit 1").name

      it "should delete a row", ->
        res = assert pg\query [[
          delete from "hello_world" where id = 1
        ]]

        assert.same { affected_rows: 1 }, res
        assert.same nil,
          unpack(pg\query "select * from hello_world where id = 1") or nil

      it "should truncate table", ->
        res = assert pg\query "truncate hello_world"
        assert.same true, res

      it "should make many select queries", ->
        for i=1,20
          assert pg\query [[update "hello_world" SET "name" = 'blahblah' where id = ]] .. i
          assert pg\query [[ select * from hello_world ]]

  it "should deserialize types correctly", ->
    assert pg\query [[
      create table types_test (
        id serial not null,
        name text default 'hello',
        subname varchar default 'world',
        count integer default 100,
        flag boolean default false,
        count2 double precision default 1.2,

        primary key (id)
      )
    ]]

    assert pg\query [[
      insert into types_test (name) values ('hello')
    ]]


    res = assert pg\query [[
      select * from types_test order by id asc limit 1
    ]]

    assert.same {
      {
        id: 1
        name: "hello"
        subname: "world"
        count: 100
        flag: false
        count2: 1.2
      }
    }, res

    assert pg\query [[
      drop table types_test
    ]]

  it "should convert null", ->
    pg.convert_null = true
    res = assert pg\query "select null the_null"
    assert pg.NULL == res[1].the_null

  it "should convert to custom null", ->
    pg.convert_null = true
    n = {"hello"}
    pg.NULL = n
    res = assert pg\query "select null the_null"
    assert n == res[1].the_null

  it "should return error message", ->
    status, err = pg\query "select * from blahlbhabhabh"
    assert.falsy status
    assert.same [[ERROR: relation "blahlbhabhabh" does not exist (15)]], err

  it "should allow a query after getting an error", ->
    status, err = pg\query "select * from blahlbhabhabh"
    assert.falsy status
    res = pg\query "select 1"
    assert.truthy res

  it "should error when connecting with invalid server", ->
    pg2 = Postgres {
      database: "doesnotexist"
    }

    status, err = pg2\connect!
    assert.falsy status
    assert.same [[FATAL: database "doesnotexist" does not exist]], err

  teardown ->
    pg\disconnect!
    os.execute "dropdb -U postgres '#{DB}'"

describe "pgmoon without server", ->
  escape_ident = {
    { "dad", '"dad"' }
    { "select", '"select"' }
    { 'love"fish', '"love""fish"' }
  }

  escape_literal = {
    { 3434, "3434" }
    { 34.342, "34.342" }
    { "cat's soft fur", "'cat''s soft fur'" }
    { true, "TRUE" }
  }

  local pg
  before_each ->
    pg = Postgres!

  for {ident, expected} in *escape_ident
    it "should escape identifier '#{ident}'", ->
      assert.same expected, pg\escape_identifier ident

  for {lit, expected} in *escape_literal
    it "should escape literal '#{lit}'", ->
      assert.same expected, pg\escape_literal lit
