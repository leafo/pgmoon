
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

  it "creates and drop table", ->
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

    it "inserts a row", ->
      res = assert pg\query [[
        insert into "hello_world" ("name", "count") values ('hi', 100)
      ]]

      assert.same { affected_rows: 1 }, res

    it "inserts a row with return value", ->
      res = assert pg\query [[
        insert into "hello_world" ("name", "count") values ('hi', 100) returning "id"
      ]]

      assert.same {
        affected_rows: 1
        { id: 1 }
      }, res

    it "selects from empty table", ->
      res = assert pg\query [[select * from hello_world limit 2]]
      assert.same {}, res

    it "deletes nothing", ->
      res = assert pg\query [[delete from hello_world]]
      assert.same { affected_rows: 0 }, res

    it "update no rows", ->
      res = assert pg\query [[update "hello_world" SET "name" = 'blahblah']]
      assert.same { affected_rows: 0 }, res

    describe "with rows", ->
      before_each ->
        for i=1,10
          assert pg\query [[
            insert into "hello_world" ("name", "count")
              values (']] .. "thing_#{i}" .. [[', ]] .. i .. [[)
          ]]

      it "select some rows", ->
        res = assert pg\query [[ select * from hello_world ]]
        assert.same "table", type(res)
        assert.same 10, #res


      it "update rows", ->
        res = assert pg\query [[
          update "hello_world" SET "name" = 'blahblah'
        ]]

        assert.same { affected_rows: 10 }, res
        assert.same "blahblah",
          unpack(pg\query "select name from hello_world limit 1").name

      it "delete a row", ->
        res = assert pg\query [[
          delete from "hello_world" where id = 1
        ]]

        assert.same { affected_rows: 1 }, res
        assert.same nil,
          unpack(pg\query "select * from hello_world where id = 1") or nil

      it "truncate table", ->
        res = assert pg\query "truncate hello_world"
        assert.same true, res

      it "make many select queries", ->
        for i=1,20
          assert pg\query [[update "hello_world" SET "name" = 'blahblah' where id = ]] .. i
          assert pg\query [[ select * from hello_world ]]


      -- single call, multiple queries
      describe "multi-queries #multi", ->
        it "gets two results", ->
          res, num_queries = assert pg\query [[
            select id, flag from hello_world order by id asc limit 2;
            select id, flag from hello_world order by id asc limit 2 offset 2;
          ]]

          assert.same 2, num_queries
          assert.same {
            {
              { id: 1, flag: true }
              { id: 2, flag: true }
            }

            {
              { id: 3, flag: true }
              { id: 4, flag: true }
            }
          }, res

        it "gets three results", ->
          res, num_queries = assert pg\query [[
            select id, flag from hello_world order by id asc limit 2;
            select id, flag from hello_world order by id asc limit 2 offset 2;
            select id, flag from hello_world order by id asc limit 2 offset 4;
          ]]

          assert.same 3, num_queries
          assert.same {
            {
              { id: 1, flag: true }
              { id: 2, flag: true }
            }

            {
              { id: 3, flag: true }
              { id: 4, flag: true }
            }

            {
              { id: 5, flag: true }
              { id: 6, flag: true }
            }
          }, res


        it "does multiple updates", ->
          res, num_queries = assert pg\query [[
            update hello_world set flag = false where id = 3;
            update hello_world set flag = true;
          ]]

          assert.same 2, num_queries
          assert.same {
            { affected_rows: 1 }
            { affected_rows: 10 }
          }, res


        it "does mix update and select", ->
          res, num_queries = assert pg\query [[
            update hello_world set flag = false where id = 3;
            select id, flag from hello_world where id = 3
          ]]

          assert.same 2, num_queries
          assert.same {
            { affected_rows: 1 }
            {
              { id: 3, flag: false }
            }
          }, res


        it "returns partial result on error", ->
          res, err, partial, num_queries = pg\query [[
            select id, flag from hello_world order by id asc limit 1;
            select id, flag from jello_world limit 1;
          ]]

          assert.same {
            err: [[ERROR: relation "jello_world" does not exist (104)]]
            num_queries: 1
            partial: {
              { id: 1, flag: true }
            }
          }, { :res, :err, :partial, :num_queries }


  it "deserializes types correctly", ->
    assert pg\query [[
      create table types_test (
        id serial not null,
        name text default 'hello',
        subname varchar default 'world',
        count integer default 100,
        flag boolean default false,
        count2 double precision default 1.2,
        bytes bytea default E'\\x68656c6c6f5c20776f726c6427',
        config json default '{"hello": "world", "arr": [1,2,3], "nested": {"foo": "bar"}}',
        bconfig jsonb default '{"hello": "world", "arr": [1,2,3], "nested": {"foo": "bar"}}',
        uuids uuid[] default ARRAY['00000000-0000-0000-0000-000000000000']::uuid[],

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
        bytes: 'hello\\ world\''
        config: { hello: "world", arr: {1,2,3}, nested: {foo: "bar"} }
        bconfig: { hello: "world", arr: {1,2,3}, nested: {foo: "bar"} }
        uuids: {'00000000-0000-0000-0000-000000000000'}
      }
    }, res

    assert pg\query [[
      drop table types_test
    ]]

  describe "json", ->
    import encode_json, decode_json from require "pgmoon.json"

    it "encodes json type", ->
      t = { hello: "world" }
      enc = encode_json t
      assert.same [['{"hello":"world"}']], enc

      t = { foo: "some 'string'" }
      enc = encode_json t
      assert.same [['{"foo":"some ''string''"}']], enc

    it "encodes json type with custom escaping", ->
      escape = (v) ->
        "`#{v}`"

      t = { hello: "world" }
      enc = encode_json t, escape
      assert.same [[`{"hello":"world"}`]], enc

    it "serialize correctly", ->
      assert pg\query [[
        create table json_test (
          id serial not null,
          config json,
          primary key (id)
        )
      ]]

      assert pg\query "insert into json_test (config) values (#{encode_json {foo: "some 'string'"}})"
      res = assert pg\query [[select * from json_test where id = 1]]
      assert.same { foo: "some 'string'" }, res[1].config

      assert pg\query "insert into json_test (config) values (#{encode_json {foo: "some \"string\""}})"
      res = assert pg\query [[select * from json_test where id = 2]]
      assert.same { foo: "some \"string\"" }, res[1].config

      assert pg\query [[
        drop table json_test
      ]]

  describe "arrays", ->
    import decode_array, encode_array from require "pgmoon.arrays"

    it "converts table to array", ->
      import PostgresArray from require "pgmoon.arrays"

      array = PostgresArray {1,2,3}
      assert.same {1,2,3}, array
      assert PostgresArray.__base == getmetatable array

    it "encodes array value", ->
      assert.same "ARRAY[1,2,3]", encode_array {1,2,3}
      assert.same "ARRAY['hello','world']", encode_array {"hello", "world"}
      assert.same "ARRAY[[4,5],[6,7]]", encode_array {{4,5}, {6,7}}

    it "decodes empty array value", ->
      assert.same {}, decode_array "{}"
      import PostgresArray from require "pgmoon.arrays"
      assert PostgresArray.__base == getmetatable decode_array "{}"

    it "decodes numeric array", ->
      assert.same {1}, decode_array "{1}", tonumber
      assert.same {1, 3}, decode_array "{1,3}", tonumber

      assert.same {5.3}, decode_array "{5.3}", tonumber
      assert.same {1.2, 1.4}, decode_array "{1.2,1.4}", tonumber

    it "decodes multi-dimensional numeric array", ->
      assert.same {{1}}, decode_array "{{1}}", tonumber
      assert.same {{1,2,3},{4,5,6}}, decode_array "{{1,2,3},{4,5,6}}", tonumber

    it "decodes literal array", ->
      assert.same {"hello"}, decode_array "{hello}"
      assert.same {"hello", "world"}, decode_array "{hello,world}"

    it "decodes multi-dimensional literal array", ->
      assert.same {{"hello"}}, decode_array "{{hello}}"
      assert.same {{"hello", "world"}, {"foo", "bar"}},
        decode_array "{{hello,world},{foo,bar}}"

    it "decodes string array", ->
      assert.same {"hello world"}, decode_array [[{"hello world"}]]

    it "decodes multi-dimensional string array", ->
      assert.same {{"hello world"}, {"yes"}},
        decode_array [[{{"hello world"},{"yes"}}]]

    it "decodes string escape sequences", ->
      assert.same {[[hello \ " yeah]]}, decode_array [[{"hello \\ \" yeah"}]]

    it "fails to decode invalid array syntax", ->
      assert.has_error ->
        decode_array [[{1, 2, 3}]]

    it "decodes literal starting with numbers array", ->
      assert.same {"1one"}, decode_array "{1one}"
      assert.same {"1one", "2two"}, decode_array "{1one,2two}"

    describe "with table", ->
      before_each ->
        pg\query "drop table if exists arrays_test"

      it "loads integer arrays from table", ->
        assert pg\query "create table arrays_test (
          a integer[],
          b int2[],
          c int8[],
          d numeric[],
          e float4[],
          f float8[]
        )"

        num_cols = 6
        assert pg\query "insert into arrays_test
          values (#{"'{1,2,3}',"\rep(num_cols)\sub 1, -2})"

        assert pg\query "insert into arrays_test
          values (#{"'{9,5,1}',"\rep(num_cols)\sub 1, -2})"

        assert.same {
          {
            a: {1,2,3}
            b: {1,2,3}
            c: {1,2,3}
            d: {1,2,3}
            e: {1,2,3}
            f: {1,2,3}
          }
          {
            a: {9,5,1}
            b: {9,5,1}
            c: {9,5,1}
            d: {9,5,1}
            e: {9,5,1}
            f: {9,5,1}
          }
        }, (pg\query "select * from arrays_test")

      it "loads string arrays from table", ->
        assert pg\query "create table arrays_test (
          a text[],
          b varchar[],
          c char(3)[]
        )"

        num_cols = 3
        assert pg\query "insert into arrays_test
          values (#{"'{one,two}',"\rep(num_cols)\sub 1, -2})"
        assert pg\query "insert into arrays_test
          values (#{"'{1,2,3}',"\rep(num_cols)\sub 1, -2})"

        assert.same {
          {
            a: {"one", "two"}
            b: {"one", "two"}
            c: {"one", "two"}
          }
          {
            a: {"1", "2", "3"}
            b: {"1", "2", "3"}
            c: {"1  ", "2  ", "3  "}
          }
        }, (pg\query "select * from arrays_test")

      it "loads string arrays from table", ->
        assert pg\query "create table arrays_test (ids boolean[])"
        assert pg\query "insert into arrays_test (ids) values ('{t,f}')"
        assert pg\query "insert into arrays_test (ids) values ('{{t,t},{t,f},{f,f}}')"

        assert.same {
          { ids: {true, false} }
          { ids: {
            {true, true}
            {true, false}
            {false, false}
          } }
        }, (pg\query "select * from arrays_test")


  it "converts null", ->
    pg.convert_null = true
    res = assert pg\query "select null the_null"
    assert pg.NULL == res[1].the_null

  it "converts to custom null", ->
    pg.convert_null = true
    n = {"hello"}
    pg.NULL = n
    res = assert pg\query "select null the_null"
    assert n == res[1].the_null

  it "encodes bytea type", ->
    n = { { bytea: "encoded' string\\" } }
    enc = pg\encode_bytea n[1].bytea
    res = assert pg\query "select #{enc}::bytea"
    assert.same n, res

  it "returns error message", ->
    status, err = pg\query "select * from blahlbhabhabh"
    assert.falsy status
    assert.same [[ERROR: relation "blahlbhabhabh" does not exist (15)]], err

  it "allows a query after getting an error", ->
    status, err = pg\query "select * from blahlbhabhabh"
    assert.falsy status
    res = pg\query "select 1"
    assert.truthy res

  it "errors when connecting with invalid server", ->
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
    it "escapes identifier '#{ident}'", ->
      assert.same expected, pg\escape_identifier ident

  for {lit, expected} in *escape_literal
    it "escapes literal '#{lit}'", ->
      assert.same expected, pg\escape_literal lit
