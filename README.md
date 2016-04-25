# pgmoon

[![Build Status](https://travis-ci.org/leafo/pgmoon.svg?branch=master)](https://travis-ci.org/leafo/pgmoon)

pgmoon is a PostgreSQL client library written in pure Lua (MoonScript).

pgmoon was originally designed for use in [OpenResty][5] to take advantage of the
[cosocket api][4] to provide asynchronous queries but it also works in the regular
Lua environment as well using [LuaSocket][1] (and optionally [LuaCrypto][2] for
MD5 authentication)

It's a perfect candidate for running your queries both inside OpenResty's
environment and on the command line (eg. tests) in web frameworks like [Lapis][3].

## Install

```bash
$ luarocks install pgmoon
```

## Example

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new({
  host = "127.0.0.1",
  port = "5432",
  database = "mydb",
  user = "postgres"
})

assert(pg:connect())

local res = assert(pg:query("select * from users where username = " ..
  pg:escape_literal("leafo")))
```

If you are using OpenResty you should relinquish the socket after you are done
with it so it can be reused in future requests:

```lua
pg:keepalive()
```

## Reference

Functions in table returned by `require("pgmoon")`:

### `new(options={})`

Creates a new `Postgres` object. Does not connect automatically. Takes a table
of options. The table can have the following keys:

* `"host"`: the host to connect to (default: `"127.0.0.1"`)
* `"port"`: the port to connect to (default: `"5432"`)
* `"user"`: the database username to authenticate (default: `"postgres"`)
* `"database"`: the database name to connect to **required**
* `"password"`: password for authentication, optional depending on server configuration
* `"ssl"`: use an ssl connection (default: false)
* `"ssl_verify"`: verify the ssl certificate and hostname (default: false)

Methods on the `Postgres` object returned by `new`:

### success, err = postgres:connect()

Connects to the Postgres server using the credentials specified in the call to
`new`. On success returns `true`, on failure returns `nil` and the error
message.


### success, err = postgres:disconnect()

Closes the socket to the server if one is open. No other methods should be
called on the object after this other than another call to connect.


### success, err = postgres:keepalive(...)

Relinquishes socket to OpenResty socket pool via the `setkeepalive` method. Any
arguments passed here are also passed to `setkeepalive`.

### result, num_queries = postgres:query(query_string)
### result, err, partial, num_queries = postgres:query(query_string)

Sends a query to the server. On failure returns `nil` and the error message.

On success returns a result depending on the kind of query sent.

`SELECT` queries, `INSERT` with `returning`, or anything else that returns a
result set will return an array table of results. Each result is a hash table
where the key is the name of the column and the value is the result for that
row of the result.

```lua
local res = pg:query("select id, name from users")
```

Might return:

```lua
{
  {
    id = 123,
    name = "Leafo"
  },
  {
    id = 234,
    name = "Lee"
  }
}
```

Any queries that affect rows like `UPDATE`, `DELETE`, or `INSERT` return a
table result with the `affected_rows` field set to the number of rows affected.


```lua
local res = pg:query("delete from users")
```

Might return:

```lua
{
  affected_rows = 2
}
```

Any queries with no result set or updated rows will return `true`.


This method also supports sending multiple queries at once by separating them
with a `;`. The number of queries executed is returned as a second return value
after the result object. When more than one query is executed then the result
object changes slightly. It becomes a array table holding all the individual
results:

```lua
local res, num_queries = pg:query([[
  select id, name from users;
  select id, title from posts
]])
```

Might return:

```lua
num_queries = 2

res = {
  {
    {
      id = 123,
      name = "Leafo"
    },
    {
      id = 234,
      name = "Lee"
    }
  },
  {
    {
      id = 546,
      title = "My first post"
    }
  }
}
```

Similarly for queries that return affected rows or just `true`, they will be
wrapped up in an addition array table when there are multiple of them. You can
also mix the different query types as you see fit.

Because Postgres executes each query at a time, earlier ones may succeed and
further ones may fail. If there is a failure with multiple queries then the
partial result and partial number of queries executed is returned after the
error message.


### escaped = postgres:escape_literal(val)

Escapes a Lua value for use as a Postgres value interpolated into a query
string. When sending user provided data into a query you should use this method
to prevent SQL injection attacks.

### escaped = postgres:escape_identifier(val)

Escapes a Lua value for use as a Postgres identifier. This includes things like
table or column names. This does not include regular values, you should use
`escape_literal` for that. Identifier escaping is required when names collide
with built in language keywords.

### str = tostring(postgres)

Returns string representation of current state of `Postgres` object.

## Authentication types

Postgres has a handful of authentication types. pgmoon currently supports
Trust and MD5 authentication.

## Type conversion

Postgres has a very rich set of types built in. pgmoon will do its best to
convert any Postgres types into the appropriate Lua type.

All integer, floating point, and numeric types are converted into Lua's number
type. The boolean type is converted into a Lua boolean. The JSON type is
decoded into a Lua table using Lua CJSON. Lua tables can be encoded to JSON as
described below.

Any array types are automatically converted to Lua array tables. If you need to
encode an array in Lua to Postgres' array syntax you can use the
`pgmoon.arrays` module. See below.

Any other types are returned as Lua strings.

## Handling arrays

Arrays are automatically decoded when they are returned from a query. Numeric,
string, and boolean types are automatically loaded accordingly. Nested arrays
are also supported.

Use `encode_array` to encode a Lua table to array syntax for a query:

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
pg:connect()

local encode_array = require("pgmoon.arrays").encode_array
local my_array = {1,2,3,4,5}
pg:query("insert into some_table (some_arr_col) values(" .. encode_array(my_array) .. ")")
```

## Handling JSON

`json` and `jsonb` types are automatically decoded when they are returned from
a query.

Use `encode_json` to encode a Lua table to the JSON syntax for a query:

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
pg:connect()

local encode_json = require("pgmoon.json").encode_json
local my_tbl = {hello = "world"}
pg:query("insert into some_table (some_json_col) values(" .. encode_json(my_tbl) .. ")")
```

## Converting `NULL`s

By default `NULL`s in Postgres are converted to `nil`, meaning they aren't
visible in the resulting tables. If you want to convert `NULL`s to some visible
value set `convert_null` to `true` on the `Postgres` object:

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
pg:connect()

pg.convert_null = true
local res = pg:query("select NULL the_null")

assert(pg.NULL == res[1].the_null)
```

As shown above, the `NULL` value is set to `pg.NULL`. You can change this value
to make pgmoon use something else as `NULL`. For example if you're using
OpenResty you might want to reuse `ngx.null`.

# Contact

Author: Leaf Corcoran (leafo) ([@moonscript](http://twitter.com/moonscript))
Email: leafot@gmail.com
Homepage: <http://leafo.net>


# Changelog

* 1.4.0 — 2016-02-18 — Add support for decoding jsonb, add a json serializer (@thibaultCha)
* 1.3.0 — 2016-02-11 — Fix bug parsing a string that looked like a number failed, add support for using in ngx when in init context (@thibaultCha), add cleartext password auth, fix warning with md5 auth
* 1.2.0 — 2015-07-10 — Add support for PostgreSQL Arrays
* 1.1.1 — 2014-08-12 — Fix a bug with md5 auth
* 1.1.0 — 2014-05-21 — Add support for multiple queries in one call
* 1.0.0 — 2014-05-19 — Initial release

## License (MIT)

Copyright (C) 2014 by Leaf Corcoran

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.


  [1]: http://w3.impa.br/~diego/software/luasocket/
  [2]: http://mkottman.github.io/luacrypto/
  [3]: http://leafo.net/lapis
  [4]: http://wiki.nginx.org/HttpLuaModule#ngx.socket.tcp
  [5]: http://openresty.org/
