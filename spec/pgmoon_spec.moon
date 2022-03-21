
import Postgres from require "pgmoon"

unpack = table.unpack or unpack

import psql, HOST, PORT, USER, PASSWORD, DB from require "spec.util"

describe "bit library compatibility", ->
  import band, lshift, rshift from require "pgmoon.bit"

  it "lshift works the same as luabitop", ->
    assert 255 == lshift(0xff,0)
    assert 65535 == lshift(0xffff,0)
    assert 16777215 == lshift(0xffffff,0)
    assert -1 == lshift(0xffffffff,0)
    assert 65280 == lshift(0xff,8)
    assert 16711680 == lshift(0xff,16)
    assert -16777216 == lshift(0xff,24)
    assert 255 == lshift(0xff,32)
    assert 16776960 == lshift(0xffff,8)
    assert -65536 == lshift(0xffff,16)
    assert -16777216 == lshift(0xffff,24)
    assert 65535 == lshift(0xffff,32)
    assert -256 == lshift(0xffffff,8)
    assert -65536 == lshift(0xffffff,16)
    assert -16777216 == lshift(0xffffff,24)
    assert 16777215 == lshift(0xffffff,32)
    assert -256 == lshift(0xffffffff,8)
    assert -65536 == lshift(0xffffffff,16)
    assert -16777216 == lshift(0xffffffff,24)
    assert -1 == lshift(0xffffffff,32)
    assert 1 == lshift(1,0)
    assert 256 == lshift(1,8)
    assert 65536 == lshift(1,16)
    assert 16777216 == lshift(1,24)
    assert 1 == lshift(1,32)
    assert -1 == lshift(-1,0)
    assert -256 == lshift(-1,8)
    assert -65536 == lshift(-1,16)
    assert -16777216 == lshift(-1,24)
    assert -1 == lshift(-1,32)

  it "rshift works the same as luabitop", ->
    assert 255 == rshift(0xff,0)
    assert 65535 == rshift(0xffff,0)
    assert 16777215 == rshift(0xffffff,0)
    assert -1 == rshift(0xffffffff,0)
    assert 0 == rshift(0xff,8)
    assert 0 == rshift(0xff,16)
    assert 0 == rshift(0xff,24)
    assert 255 == rshift(0xff,32)
    assert 255 == rshift(0xffff,8)
    assert 0 == rshift(0xffff,16)
    assert 0 == rshift(0xffff,24)
    assert 65535 == rshift(0xffff,32)
    assert 65535 == rshift(0xffffff,8)
    assert 255 == rshift(0xffffff,16)
    assert 0 == rshift(0xffffff,24)
    assert 16777215 == rshift(0xffffff,32)
    assert 16777215 == rshift(0xffffffff,8)
    assert 65535 == rshift(0xffffffff,16)
    assert 255 == rshift(0xffffffff,24)
    assert -1 == rshift(0xffffffff,32)
    assert 1 == rshift(1,0)
    assert 0 == rshift(1,8)
    assert 0 == rshift(1,16)
    assert 0 == rshift(1,24)
    assert 1 == rshift(1,32)
    assert -1 == rshift(-1,0)
    assert 16777215 == rshift(-1,8)
    assert 65535 == rshift(-1,16)
    assert 255 == rshift(-1,24)
    assert -1 == rshift(-1,32)

  it "band works the same as luabitop", ->
    assert 0 == band(0xff,0)
    assert 0 == band(0xffff,0)
    assert 0 == band(0xffffff,0)
    assert 0 == band(0xffffffff,0)
    assert 255 == band(0xff,0xff)
    assert 65535 == band(0xffff,0xffff)
    assert 16777215 == band(0xffffff,0xffffff)
    assert -1 == band(0xffffffff,0xffffffff)
    assert 16777215 == band(0xffffffff,0xffffff)
    assert 65535 == band(0xffffffff,0xffff)
    assert 255 == band(0xffffffff,0xff)
    assert 255 == band(0xff,-1)
    assert 65535 == band(0xffff,-1)
    assert 16777215 == band(0xffffff,-1)
    assert -1 == band(0xffffffff,-1)
    assert 0 == band(-1,0)
    assert 255 == band(-1,0xff)
    assert 65535 == band(-1,0xffff)
    assert 16777215 == band(-1,0xffffff)
    assert -1 == band(-1,0xffffffff)
    assert -1 == band(-1,-1)
    assert 255 == band(0xffffffffff,0xff)


describe "pgmoon with server", ->
  setup ->
    os.execute "spec/postgres.sh start"

  teardown ->
    os.execute "spec/postgres.sh stop"

  for socket_type in *{"luasocket", "cqueues", "nginx"}
    if ngx
      unless socket_type == "nginx"
        it "(disabled)", -> pending "skipping #{socket_type} in nginx testing mode"
        continue
    else
      if socket_type == "nginx"
        it "(disabled)", -> pending "Skipping nginx tests, no ngx global available"
        continue

    describe "socket(#{socket_type})", ->
      local pg

      setup ->
        r = { psql "drop database if exists #{DB}" }
        assert 0 == r[#r], "failed to execute psql: drop database"

        r = { psql "create database #{DB}" }
        assert 0 == r[#r], "failed to execute psql: create database"

        pg = Postgres {
          database: DB
          user: USER
          password: PASSWORD
          host: HOST
          port: PORT
          :socket_type
        }
        assert pg\connect!

      teardown ->
        pg\disconnect!

      -- issue another query to make sure that the connection is stil valid
      sanity_check = ->
        assert.same {
          { one: 1 }
        }, pg\query "select 1 as one"

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

      it "settimeout()", ->
        timeout_pg = Postgres {
          host: "10.0.0.1"
          :socket_type
        }

        timeout_pg\settimeout 1000

        ok, err = timeout_pg\connect!
        assert.is_nil ok
        errors = {
          "timeout": true
          "Connection timed out": true
        }

        assert.true errors[err]

      it "keepalive()", ->
        if socket_type != "nginx"
          return pending "only available in nginx"

        assert pg\keepalive! -- put socket back into pool
        assert pg\connect! -- reconnect using same socket object
        assert pg\query "select 1"

      it "tries to connect with SSL", ->
        -- we expect a server with ssl = off
        ssl_pg = Postgres {
          database: DB
          user: USER
          password: PASSWORD
          host: HOST
          port: PORT
          ssl: true
          :socket_type
        }

        finally ->
          ssl_pg\disconnect!

        assert ssl_pg\connect!

      it "requires SSL", ->
        ssl_pg = Postgres {
          database: DB
          user: USER
          password: PASSWORD
          host: HOST
          port: PORT
          ssl: true
          ssl_required: true
          :socket_type
        }

        status, err = ssl_pg\connect!
        assert.falsy status, "connection should fail if it could not establish ssl"
        assert.same [[the server does not support SSL connections]], err

      describe "extended_query", ->
        it "query with no params", ->
          res = assert pg\extended_query "select 1 as one"
          assert.same {
            {
              one: 1
            }
          }, res

        it "simple string params", ->
          res = assert pg\extended_query "select $1 a, $2 b, $3 c, $4 d",
            "one", "two", "three", "four"

          assert.same {
            {
              a: "one"
              b: "two"
              c: "three"
              d: "four"
            }
          }, res

        it "mixed types", ->
          res = assert pg\extended_query "select $1 a, $2 b, $3 c, $4 d",
            true, false, pg.NULL, 44

          assert.same {
            {
              a: true
              b: false
              c: nil
              d: 44
            }
          }, res

        it "types don't need casting", ->
          res = assert pg\extended_query "select $1 + $1 as sum", 7

          assert.same {
            {
              sum: 14
            }
          }, res

        it "handles error when missing params", ->
          res, err = pg\extended_query "select $1 as hi"
          assert.nil res
          assert.same [[ERROR: bind message supplies 0 parameters, but prepared statement "" requires 1]], err
          sanity_check!

          -- TODO: test that we are ready to process a new query

        it "handles query with excess params", ->
          -- this does not throw an error
          res = assert pg\extended_query "select $1 as hi", 1, 2

          assert.same res, {
            {
              hi: 1
            }
          }

        it "handle passing in nil as parameter value", ->
          pg.convert_null = true
          res, err = pg\extended_query "select $1 as hi, $2 as bye", 1, nil
          pg.convert_null = false

          assert.same {
            {
              hi: 1
              bye: pg.NULL
            }
          }, res

        it "json custom serializable value", ->
          json = require("cjson")

          json_type = (v) ->
            setmetatable { v }, {
              pgmoon_serialize: (pgmoon) =>
                114, (json.encode @[1])
            }

          res = assert pg\extended_query "select $1 as a, $2 as b",
            json_type({1,2,json.null,4}), json_type({
              color: "blue"
              yes: true
              more: {"ok"}
            })

          assert.same {
            {
              a: {1,2,json.null,4}
              b: {
                color: "blue"
                yes: true
                more: {"ok"}
              }
            }
          }, res

        it "array custom serializer", ->
          numeric_array = (v) ->
            setmetatable { v }, {
              pgmoon_serialize: (pgmoon) =>
                import encode_array from require "pgmoon.arrays"
                1231, "{#{table.concat @[1], ","}}"
            }

          res = assert pg\extended_query "select $1 as a, $2 as b",
            numeric_array({4, 99, 77, -4}), numeric_array({})

          assert.same {
            {
              a: {
                4, 99, 77, -4
              }
              b: {}
            }
          }, res

          res, err = pg\extended_query "select $1 as a",
            numeric_array({"hello"})

          assert.nil res
          assert.same [[ERROR: invalid input syntax for type numeric: "hello"]], err
          sanity_check!


        it "fails on table with no serializer", ->
          res, err = pg\extended_query "select $1 as a", {"hello", world: 9}
          assert.nil res
          assert.same [[pgmoon: param 1: table does not implement pgmoon_serialize, can't serialize]], err

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

        it "selects count as a number", ->
          res = assert pg\query [[select count(*) from hello_world]]
          assert.same {
            { count: 0 }
          }, res

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
              unpack((pg\query "select name from hello_world limit 1")).name

          it "delete a row", ->
            res = assert pg\query [[
              delete from "hello_world" where id = 1
            ]]

            assert.same { affected_rows: 1 }, res
            assert.same nil,
              unpack((pg\query "select * from hello_world where id = 1")) or nil

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
                err: [[ERROR: relation "jello_world" does not exist (112)]]
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

      it "deserializes row types correctly", ->
        assert.same {
          {
            ["?column?"]: 1
          }
        }, (pg\query "select 1")


        assert.same {
          {
            ["row"]: "(1,hello,5.999)" -- we don't have a type deserializer for record type at this time
          }
        }, (pg\query "select row(1, 'hello', 5.999)")

        assert.same {
          {
            ["row"]: "(1,hello,5.999)" -- we don't have a type deserializer for record type at this time
          }
        }, (pg\query "select (1, 'hello', 5.999)")

      describe "custom deserializer", ->
        it "deserializes big integer to string", ->
          assert pg\query [[
             create table bigint_test (
               id serial not null,
               largenum bigint default 9223372036854775807,
               primary key (id)
            )
          ]]

          assert pg\query [[
            insert into bigint_test (largenum) values (default)
          ]]

          pg\set_type_deserializer 20, "bignumber", (val) => "HUGENUMBER:#{val}"
          row = unpack pg\query "select * from bigint_test"

          assert.same {
            id: 1
            largenum: "HUGENUMBER:9223372036854775807"
          }, row

      describe "notice", ->
        it "gets notice from query", ->
          res, num_queries, notifications, notices = pg\query "drop table if exists farts"

          assert.same true, res
          assert.same num_queries, 1
          assert.nil notifications
          assert.same {
            [[NOTICE: table "farts" does not exist, skipping]]
          }, notices

      describe "hstore", ->
        import encode_hstore, decode_hstore from require "pgmoon.hstore"

        describe "encoding", ->
          it "encodes hstore type", ->
            t = { foo: "bar" }
            enc = encode_hstore t
            assert.same [['"foo"=>"bar"']], enc

          it "encodes multiple pairs", ->
            t = { foo: "bar", abc: "123" }
            enc = encode_hstore t
            results = {'\'"foo"=>"bar", "abc"=>"123"\'', '\'"abc"=>"123", "foo"=>"bar"\''}
            assert(enc == results[1] or enc == results[2])

          it "escapes", ->
            t = { foo: "bar's" }
            enc = encode_hstore t
            assert.same [['"foo"=>"bar''s"']], enc

        describe "decoding", ->
          it "decodes hstore into a table", ->
            s = '"foo"=>"bar"'
            dec = decode_hstore s
            assert.same {foo: 'bar'}, dec

          it "decodes hstore with multiple parts", ->
            s = '"foo"=>"bar", "1-a"=>"anything at all"'
            assert.same {
              foo: "bar"
              "1-a": "anything at all"
            }, decode_hstore s

          it "decodes hstore with embedded quote", ->
            assert.same {
              hello: 'wo"rld'
            }, decode_hstore [["hello"=>"wo\"rld"]]

        describe "serializing", ->
          before_each ->
            assert pg\query [[
              CREATE EXTENSION hstore;
              create table hstore_test (
                id serial primary key,
                h hstore
              )
            ]]
            pg\setup_hstore!

          after_each ->
            assert pg\query [[
              DROP TABLE hstore_test;
              DROP EXTENSION hstore;
            ]]

          it "serializes correctly", ->
            assert pg\query "INSERT INTO hstore_test (h) VALUES (#{encode_hstore {foo: 'bar'}});"
            res = assert pg\query "SELECT * FROM hstore_test;"

            assert.same {foo: 'bar'}, res[1].h

          it "serializes NULL as string", ->
            assert pg\query "INSERT INTO hstore_test (h) VALUES (#{encode_hstore {foo: 'NULL'}});"
            res = assert pg\query "SELECT * FROM hstore_test;"

            assert.same 'NULL', res[1].h.foo

          it "serializes multiple pairs", ->
            assert pg\query "INSERT INTO hstore_test (h) VALUES (#{encode_hstore {abc: '123', foo: 'bar'}});"
            res = assert pg\query "SELECT * FROM hstore_test;"

            assert.same {abc: '123', foo: 'bar'}, res[1].h

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
        import decode_array, encode_array, PostgresArray from require "pgmoon.arrays"

        it "converts table to array", ->
          array = PostgresArray {1,2,3}
          assert.same {1,2,3}, array
          assert PostgresArray.__base == getmetatable array

        it "encodes array value", ->
          assert.same "ARRAY[]", encode_array {}
          assert.same "ARRAY[1,2,3]", encode_array {1,2,3}
          assert.same "ARRAY['hello','world']", encode_array {"hello", "world"}
          assert.same "ARRAY[[4,5],[6,7]]", encode_array {{4,5}, {6,7}}

        it "decodes empty array value", ->
          assert.same {}, decode_array "{}"
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

        it "decodes json array result", ->
          res = pg\query "select array(select row_to_json(t) from (values (1,'hello'), (2, 'world')) as t(id, name)) as items"
          assert.same {
            {
              items: {
                { id: 1, name: "hello" }
                { id: 2, name: "world" }
              }
            }
          }, res

        it "decodes jsonb array result", ->
          assert.same {
            {
              items: {
                { id: 442, name: "itch" }
                { id: 99, name: "zone" }
              }
            }
          }, pg\query "select array(select row_to_json(t)::jsonb from (values (442,'itch'), (99, 'zone')) as t(id, name)) as items"

        describe "serialize", ->
          ARRAY_OIDS = {
            boolean: 1000
            number: 1231
            string: 1009
          }

          serialize_value = (v) ->
            getmetatable(v).pgmoon_serialize v, pg

          it "serializes empty array", ->
            assert.same {0, "{}"}, { serialize_value PostgresArray({}) }

          it "serializes null array", ->
            assert.same {0, "{NULL}"}, { serialize_value PostgresArray({pg.NULL}) }

          it "serializes numeric array", ->
            assert.same {ARRAY_OIDS.number, "{1,2,3}"}, { serialize_value PostgresArray({1,2,3}) }
            assert.same {ARRAY_OIDS.number, "{-23892}"}, { serialize_value PostgresArray({-23892}) }

          it "serializes string array", ->
            assert.same {ARRAY_OIDS.string, '{"hello"}'}, { serialize_value PostgresArray({"hello"}) }
            assert.same {ARRAY_OIDS.string, '{"hello",NULL,"world"}'}, { serialize_value PostgresArray({"hello", pg.NULL, "world"}) }
            assert.same {ARRAY_OIDS.string, '{"hello","world"}'}, { serialize_value PostgresArray({"hello", "world"}) }
            assert.same {ARRAY_OIDS.string, [[{",","f\"f","}{","\""}]]}, { serialize_value PostgresArray({ ",", [[f"f]], "}{", '"' }) }

            res = unpack assert pg\query "select $1 val, pg_typeof($1)", PostgresArray {
              "hello"
              pg.NULL
              "world"
              ","
              [[f"f]]
              "}{"
              "'"
              '"'
            }

            assert.same "text[]", res.pg_typeof
            assert.same {
              "hello"
              pg.NULL
              "world"
              ","
              [[f"f]]
              "}{"
              "'"
              '"'
            }, res.val

          it "serializes boolean array", ->
            assert.same {ARRAY_OIDS.boolean, '{t}'}, { serialize_value PostgresArray({true}) }
            assert.same {ARRAY_OIDS.boolean, '{f,t}'}, { serialize_value PostgresArray({false, true}) }
            assert.same {ARRAY_OIDS.boolean, '{f,NULL,t}'}, { serialize_value PostgresArray({false, pg.NULL, true}) }

            res = unpack assert pg\query "select $1 val, pg_typeof($1)", PostgresArray { false, pg.NULL, true }

            assert.same "boolean[]", res.pg_typeof
            assert.same {
              false
              pg.NULL
              true
            }, res.val


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
          user: USER
          password: PASSWORD
          host: HOST
          port: PORT
          :socket_type
        }

        status, err = pg2\connect!
        assert.falsy status
        assert.same [[FATAL: database "doesnotexist" does not exist]], err

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
    { Postgres.NULL, "NULL" }
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


  describe "decode & encode int", ->
    -- sampling of 2 & 4 byte numbers, generated from:

    -- d = (s, len=#s) ->
    --   "[string.char(#{table.concat {string.byte s, 1,len}, ", "})]: #{decode_int s, len}"

    -- for i=1,255,13
    --   print d "#{string.char i}\0\0\0"
    --   print d "\0#{string.char i}\0\0"
    --   print d "\0\0#{string.char i}\0"
    --   print d "\0\0\0#{string.char i}"

    --   print d "\0#{string.char i + 1}\0#{string.char i}"
    --   print d "#{string.char i + 1}\0#{string.char i}\0"

    -- for i=1,255,13
    --   print d "#{string.char i}\0"
    --   print d "\0#{string.char i}"
    --   print d "#{string.char i + 1}#{string.char i}"

    numbers4 = {
      [string.char(1, 0, 0, 0)]: 16777216
      [string.char(0, 1, 0, 0)]: 65536
      [string.char(0, 0, 1, 0)]: 256
      [string.char(0, 0, 0, 1)]: 1
      [string.char(0, 2, 0, 1)]: 131073
      [string.char(2, 0, 1, 0)]: 33554688
      [string.char(14, 0, 0, 0)]: 234881024
      [string.char(0, 14, 0, 0)]: 917504
      [string.char(0, 0, 14, 0)]: 3584
      [string.char(0, 0, 0, 14)]: 14
      [string.char(0, 15, 0, 14)]: 983054
      [string.char(15, 0, 14, 0)]: 251661824
      [string.char(27, 0, 0, 0)]: 452984832
      [string.char(0, 27, 0, 0)]: 1769472
      [string.char(0, 0, 27, 0)]: 6912
      [string.char(0, 0, 0, 27)]: 27
      [string.char(0, 28, 0, 27)]: 1835035
      [string.char(28, 0, 27, 0)]: 469768960
      [string.char(40, 0, 0, 0)]: 671088640
      [string.char(0, 40, 0, 0)]: 2621440
      [string.char(0, 0, 40, 0)]: 10240
      [string.char(0, 0, 0, 40)]: 40
      [string.char(0, 41, 0, 40)]: 2687016
      [string.char(41, 0, 40, 0)]: 687876096
      [string.char(53, 0, 0, 0)]: 889192448
      [string.char(0, 53, 0, 0)]: 3473408
      [string.char(0, 0, 53, 0)]: 13568
      [string.char(0, 0, 0, 53)]: 53
      [string.char(0, 54, 0, 53)]: 3538997
      [string.char(54, 0, 53, 0)]: 905983232
      [string.char(66, 0, 0, 0)]: 1107296256
      [string.char(0, 66, 0, 0)]: 4325376
      [string.char(0, 0, 66, 0)]: 16896
      [string.char(0, 0, 0, 66)]: 66
      [string.char(0, 67, 0, 66)]: 4390978
      [string.char(67, 0, 66, 0)]: 1124090368
      [string.char(79, 0, 0, 0)]: 1325400064
      [string.char(0, 79, 0, 0)]: 5177344
      [string.char(0, 0, 79, 0)]: 20224
      [string.char(0, 0, 0, 79)]: 79
      [string.char(0, 80, 0, 79)]: 5242959
      [string.char(80, 0, 79, 0)]: 1342197504
      [string.char(92, 0, 0, 0)]: 1543503872
      [string.char(0, 92, 0, 0)]: 6029312
      [string.char(0, 0, 92, 0)]: 23552
      [string.char(0, 0, 0, 92)]: 92
      [string.char(0, 93, 0, 92)]: 6094940
      [string.char(93, 0, 92, 0)]: 1560304640
      [string.char(105, 0, 0, 0)]: 1761607680
      [string.char(0, 105, 0, 0)]: 6881280
      [string.char(0, 0, 105, 0)]: 26880
      [string.char(0, 0, 0, 105)]: 105
      [string.char(0, 106, 0, 105)]: 6946921
      [string.char(106, 0, 105, 0)]: 1778411776
      [string.char(118, 0, 0, 0)]: 1979711488
      [string.char(0, 118, 0, 0)]: 7733248
      [string.char(0, 0, 118, 0)]: 30208
      [string.char(0, 0, 0, 118)]: 118
      [string.char(0, 119, 0, 118)]: 7798902
      [string.char(119, 0, 118, 0)]: 1996518912
      [string.char(131, 0, 0, 0)]: -2097152000
      [string.char(0, 131, 0, 0)]: 8585216
      [string.char(0, 0, 131, 0)]: 33536
      [string.char(0, 0, 0, 131)]: 131
      [string.char(0, 132, 0, 131)]: 8650883
      [string.char(132, 0, 131, 0)]: -2080341248
      [string.char(144, 0, 0, 0)]: -1879048192
      [string.char(0, 144, 0, 0)]: 9437184
      [string.char(0, 0, 144, 0)]: 36864
      [string.char(0, 0, 0, 144)]: 144
      [string.char(0, 145, 0, 144)]: 9502864
      [string.char(145, 0, 144, 0)]: -1862234112
      [string.char(157, 0, 0, 0)]: -1660944384
      [string.char(0, 157, 0, 0)]: 10289152
      [string.char(0, 0, 157, 0)]: 40192
      [string.char(0, 0, 0, 157)]: 157
      [string.char(0, 158, 0, 157)]: 10354845
      [string.char(158, 0, 157, 0)]: -1644126976
      [string.char(170, 0, 0, 0)]: -1442840576
      [string.char(0, 170, 0, 0)]: 11141120
      [string.char(0, 0, 170, 0)]: 43520
      [string.char(0, 0, 0, 170)]: 170
      [string.char(0, 171, 0, 170)]: 11206826
      [string.char(171, 0, 170, 0)]: -1426019840
      [string.char(183, 0, 0, 0)]: -1224736768
      [string.char(0, 183, 0, 0)]: 11993088
      [string.char(0, 0, 183, 0)]: 46848
      [string.char(0, 0, 0, 183)]: 183
      [string.char(0, 184, 0, 183)]: 12058807
      [string.char(184, 0, 183, 0)]: -1207912704
      [string.char(196, 0, 0, 0)]: -1006632960
      [string.char(0, 196, 0, 0)]: 12845056
      [string.char(0, 0, 196, 0)]: 50176
      [string.char(0, 0, 0, 196)]: 196
      [string.char(0, 197, 0, 196)]: 12910788
      [string.char(197, 0, 196, 0)]: -989805568
      [string.char(209, 0, 0, 0)]: -788529152
      [string.char(0, 209, 0, 0)]: 13697024
      [string.char(0, 0, 209, 0)]: 53504
      [string.char(0, 0, 0, 209)]: 209
      [string.char(0, 210, 0, 209)]: 13762769
      [string.char(210, 0, 209, 0)]: -771698432
      [string.char(222, 0, 0, 0)]: -570425344
      [string.char(0, 222, 0, 0)]: 14548992
      [string.char(0, 0, 222, 0)]: 56832
      [string.char(0, 0, 0, 222)]: 222
      [string.char(0, 223, 0, 222)]: 14614750
      [string.char(223, 0, 222, 0)]: -553591296
      [string.char(235, 0, 0, 0)]: -352321536
      [string.char(0, 235, 0, 0)]: 15400960
      [string.char(0, 0, 235, 0)]: 60160
      [string.char(0, 0, 0, 235)]: 235
      [string.char(0, 236, 0, 235)]: 15466731
      [string.char(236, 0, 235, 0)]: -335484160
      [string.char(248, 0, 0, 0)]: -134217728
      [string.char(0, 248, 0, 0)]: 16252928
      [string.char(0, 0, 248, 0)]: 63488
      [string.char(0, 0, 0, 248)]: 248
      [string.char(0, 249, 0, 248)]: 16318712
      [string.char(249, 0, 248, 0)]: -117377024

    }

    numbers2 = {
      [string.char(1, 0)]: 256
      [string.char(0, 1)]: 1
      [string.char(2, 1)]: 513
      [string.char(14, 0)]: 3584
      [string.char(0, 14)]: 14
      [string.char(15, 14)]: 3854
      [string.char(27, 0)]: 6912
      [string.char(0, 27)]: 27
      [string.char(28, 27)]: 7195
      [string.char(40, 0)]: 10240
      [string.char(0, 40)]: 40
      [string.char(41, 40)]: 10536
      [string.char(53, 0)]: 13568
      [string.char(0, 53)]: 53
      [string.char(54, 53)]: 13877
      [string.char(66, 0)]: 16896
      [string.char(0, 66)]: 66
      [string.char(67, 66)]: 17218
      [string.char(79, 0)]: 20224
      [string.char(0, 79)]: 79
      [string.char(80, 79)]: 20559
      [string.char(92, 0)]: 23552
      [string.char(0, 92)]: 92
      [string.char(93, 92)]: 23900
      [string.char(105, 0)]: 26880
      [string.char(0, 105)]: 105
      [string.char(106, 105)]: 27241
      [string.char(118, 0)]: 30208
      [string.char(0, 118)]: 118
      [string.char(119, 118)]: 30582
      [string.char(131, 0)]: 33536
      [string.char(0, 131)]: 131
      [string.char(132, 131)]: 33923
      [string.char(144, 0)]: 36864
      [string.char(0, 144)]: 144
      [string.char(145, 144)]: 37264
      [string.char(157, 0)]: 40192
      [string.char(0, 157)]: 157
      [string.char(158, 157)]: 40605
      [string.char(170, 0)]: 43520
      [string.char(0, 170)]: 170
      [string.char(171, 170)]: 43946
      [string.char(183, 0)]: 46848
      [string.char(0, 183)]: 183
      [string.char(184, 183)]: 47287
      [string.char(196, 0)]: 50176
      [string.char(0, 196)]: 196
      [string.char(197, 196)]: 50628
      [string.char(209, 0)]: 53504
      [string.char(0, 209)]: 209
      [string.char(210, 209)]: 53969
      [string.char(222, 0)]: 56832
      [string.char(0, 222)]: 222
      [string.char(223, 222)]: 57310
      [string.char(235, 0)]: 60160
      [string.char(0, 235)]: 235
      [string.char(236, 235)]: 60651
      [string.char(248, 0)]: 63488
      [string.char(0, 248)]: 248
      [string.char(249, 248)]: 63992
    }

    it "encodes and decodes 4 bytes", ->
      for str, num in pairs numbers4
        en = pg\encode_int num, 4
        assert.same 4, #en
        assert.same str, en
        assert.same num, pg\decode_int en

    it "encodes and decodes 2 bytes", ->
      for str, num in pairs numbers2
        en = pg\encode_int num, 2
        assert.same 2, #en
        assert.same str, en
        assert.same num, pg\decode_int en
