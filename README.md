# pgmoon

[![Build Status](https://travis-ci.org/leafo/pgmoon.svg?branch=master)](https://travis-ci.org/leafo/pgmoon)

pgmoon is a PostgreSQL client library written in pure Lua (MoonScript).

pgmoon was originally designed for use in [OpenResty][5] to take advantage of
the [cosocket api][4] to provide asynchronous queries but it also works in the
regular Lua environment as well using [LuaSocket][1] (and optionally
[luaossl](https://luarocks.org/modules/daurnimator/luaossl) or [LuaCrypto][2] for MD5 authentication and [LuaSec][6] for SSL connections).
pgmoon can also use [cqueues][]' socket when passed `"cqueues"` as the socket
type when instantiating.

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

local res = assert(pg:query("select * from users where username = $1", "leafo"))
```

If you are using OpenResty you can relinquish the socket after you
are done with it so it can be reused in future requests with built-in connection pooling:

```lua
pg:keepalive()
```

Alternatively whether using OpenResty or not, you can use 3rd party connection pooling with
[PgBouncer](https://pgbouncer.github.io/) or — for more complex installations — [Pgpool](http://www.pgpool.net/mediawiki/index.php/Main_Page).

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
* `"ssl"`: enable ssl (default: `false`)
* `"ssl_verify"`: verify server certificate (default: `nil`)
* `"ssl_required"`: abort the connection if the server does not support SSL connections (default: `nil`)
* `"pool"`: optional name of pool to use when using OpenResty cosocket (defaults to `"#{host}:#{port}:#{database}"`)
* `"socket_type"`: optional, the type of socket to use, one of: `"nginx"`, `"luasocket"`, `cqueues` (default: `"nginx"` if in nginx, `"luasocket"` otherwise)

Methods on the `Postgres` object returned by `new`:

### success, err = postgres:connect()

Connects to the Postgres server using the credentials specified in the call to
`new`. On success returns `true`, on failure returns `nil` and the error
message.


### postgres:settimeout(time)

Sets the timeout value (in milliseconds) for all socket operations (connect,
write, receive). This function does not have any return values.


### success, err = postgres:disconnect()

Closes the socket to the server if one is open. No other methods should be
called on the object after this other than another call to connect.


### success, err = postgres:keepalive(...)

Relinquishes socket to OpenResty socket pool via the `setkeepalive` method. Any
arguments passed here are also passed to `setkeepalive`.

### result, num_queries = postgres:query(query_string, params...)
### result, err, partial, num_queries = postgres:query(query_string, params...)

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
to prevent SQL injection attacks. Note: you do not need this method when using
parameterized queries.

### escaped = postgres:escape_identifier(val)

Escapes a Lua value for use as a Postgres identifier. This includes things like
table or column names. This does not include regular values, you should use
`escape_literal` for that. Identifier escaping is required when names collide
with built in language keywords. Note: you do not need this method when using
parameterized queries.

### str = tostring(postgres)

Returns string representation of current state of `Postgres` object.

## SSL connections

pgmoon can establish an SSL connection to a Postgres server. It can also refuse
to connect to it if the server does not support SSL.
Just as pgmoon depends on LuaSocket for usage outside of OpenResty, it depends
on LuaSec for SSL connections in such contexts.

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new({
  host = "127.0.0.1",
  ssl = true, -- enable SSL
  ssl_verify = true, -- verify server certificate
  ssl_required = true, -- abort if the server does not support SSL connections
  cafile = "...", -- certificate authority (LuaSec only)
  cert = "...", -- client certificate (LuaSec only)
  key = "...", -- client key (LuaSec only)
})

assert(pg:connect())
```

In OpenResty, make sure to configure the [lua_ssl_trusted_certificate][7]
directive if you wish to verify the server certificate, as the LuaSec-only
options become irrelevant in that case.

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

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
pg:connect()

local my_array = {1,2,3,4,5}
local res = pg:query("insert into some_table (some_arr_col) values($1)", pg:as_array(my_array))
```

## Handling JSON

`json` and `jsonb` types are automatically decoded when they are returned from
a query.

Use `pg:as_json` to encode a Lua table to the JSON syntax for a query:

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
pg:connect()

local my_tbl = {hello = "world"}
local res = pg:query("insert into some_table (some_json_col) values($1)", pg:as_json(my_tbl))
```

## Handling hstore

Because `hstore` is an extension type, a query is reuired to find out the type
id before pgmoon can automatically decode it. Call the `setup_hstore` method on
your connection object after connecting to set it up.

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
pg:connect()
pg:setup_hstore()
```

Use `pg:as_hstore` to encode a Lua table into hstore syntax when updating and
inserting:

```lua
local tbl = {foo = "bar"}
local res = pg:query("insert into some_table (hstore_col) values($1)", pg:as_hstore(tbl))
```

You can manually decode a hstore value from string using the `decode_hstore`
function. This is only required if you didn't call `setup_hstore`.

```lua
local decode_hstore = require("pgmoon.hstore").decode_hstore
local res = pg:query("select * from some_table")
local hstore_tbl = decode_hstore(res[1].hstore_col)
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

If the `NULL` value is required in a query parameter, you can pass the `Postgres` object's `NULL`
property:

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
pg:connect()

local res = pg:query("select coalesce($1, 'example') AS val", pg.NULL)

assert("example" == res[1].val)
```

Passing `nil` is error prone due to the way Lua handles array values; trailing `nil`s are always
omitted. By passing `pg:NULL` your `NULL` value will always be processed by pgmoon as intended. So
for values that may be `NULL`:

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
pg:connect()

local res = pg:query("insert into log_table (ip, url, referrer) VALUES($1, $2, $3)",
                     ngx.var.remote_addr,
                     ngx.var.uri,
                     ngx.req.get_headers()["Referer"] or pg:NULL)
```

# Contact

Author: Leaf Corcoran (leafo) ([@moonscript](http://twitter.com/moonscript))
Email: leafot@gmail.com
Homepage: <http://leafo.net>


# Changelog

* 1.10.0 — 2019-04-15 - support luaossl for crypto functions, added better error when missing crypto library
* 1.9.0 — 2018-04-02 - nginx pool name includes user, connection reports name as `pgmoon`
* 1.8.0 — 2016-11-07 — Add cqueues support, SSL calling fix for Nginx cosocket (@thibaultCha)
* 1.7.0 — 2016-09-21 — Add to opm, add support for openresty pool, better default pool, support for hstore (@edan)
* 1.6.0 — 2016-07-21 — Add support for json and jsonb array decoding
* 1.5.0 — 2016-07-12 — Add SSL support (@thibaultCha), Add UUID array type (@edan), Add support for notifications (@starius)
* 1.4.0 — 2016-02-18 — Add support for decoding jsonb, add a json serializer (@thibaultCha)
* 1.3.0 — 2016-02-11 — Fix bug parsing a string that looked like a number failed, add support for using in ngx when in init context (@thibaultCha), add cleartext password auth, fix warning with md5 auth
* 1.2.0 — 2015-07-10 — Add support for PostgreSQL Arrays
* 1.1.1 — 2014-08-12 — Fix a bug with md5 auth
* 1.1.0 — 2014-05-21 — Add support for multiple queries in one call
* 1.0.0 — 2014-05-19 — Initial release

## License (MIT)

Copyright (C) 2016 by Leaf Corcoran

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
  [4]: https://github.com/openresty/lua-nginx-module#ngxsockettcp
  [5]: https://openresty.org/
  [6]: https://github.com/brunoos/luasec
  [7]: https://github.com/openresty/lua-nginx-module#lua_ssl_trusted_certificate
  [cqueues]: http://25thandclement.com/~william/projects/cqueues.html
