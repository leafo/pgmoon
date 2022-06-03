# pgmoon

![test](https://github.com/leafo/pgmoon/workflows/test/badge.svg)

> **Note:** Have you updated from an older version of OpenResty? You must update to
> pgmoon 1.12 or above, due to a change in Lua pattern compatibility to avoid incorrect 
> results from queries that return affected rows.

**pgmoon** is a PostgreSQL client library written in pure Lua (MoonScript).

**pgmoon** was originally designed for use in [OpenResty][] to take advantage
of the [cosocket
api](https://github.com/openresty/lua-nginx-module#ngxsockettcp) to provide
asynchronous queries but it also works in the regular any Lua environment where
[LuaSocket][] or [cqueues][] is available.

It's a perfect candidate for running your queries both inside OpenResty's
environment and on the command line (eg. tests) in web frameworks like [Lapis][].

## Install

```bash
$ luarocks install pgmoon
```

<details>
<summary>Using <a href="https://opm.openresty.org/">OpenResty's OPM</a></summary>

```bash
$ opm get leafo/pgmoon
```

</details>


### Dependencies

pgmoon supports a wide range of environments and libraries, so it may be
necessary to install additional dependencies depending on how you intend to
communicate with the database:

> **Tip:** If you're using OpenResty then no additional dependencies are needed
> (generally, a crypto library may be necessary for some authentication
> methods)

A socket implementation **is required** to use pgmoon, depending on the
environment you can chose one:

* [OpenResty][] &mdash; The built in socket is used, no additional dependencies necessary
* [LuaSocket][] &mdash; `luarocks install luasocket`
* [cqueues][] &mdash; `luarocks install cqueues`

If you're on PUC Lua 5.1 or 5.2 then you will need a bit libray (not needed for LuaJIT):

```bash
$ luarocks install luabitop
```

If you want to use JSON types you will need lua-cjson

```bash
$ luarocks install lua-cjson
```

SSL connections may require an additional dependency:

* OpenResty &mdash; `luarocks install lua-resty-openssl`
* LuaSocket &mdash; `luarocks install luasec`
* cqueues &mdash; `luarocks install luaossl`

Password authentication may require a crypto library, [luaossl][].

```bash
$ luarocks install luaossl
```
> **Note:** [LuaCrypto][] can be used as a fallback, but the library is abandoned and not recommended for use

> **Note:** Use within [OpenResty][] will prioritize built  in functions if possible

Parsing complex types like Arrays and HStore requires `lpeg` to be installed.

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

local res = assert(pg:query("select * from users where status = 'active' limit 20")

assert(pg:query("update users set name = $1 where id = $2", "leafo", 99))

```

If you are using OpenResty you can relinquish the socket to the connection pool
after you are done with it so it can be reused in future requests:

```lua
pg:keepalive()
```

## Considerations

PostgreSQL allows for results to use the same field name multiple times.
Because results are extracted into Lua tables, repeated fields will be
overwritten and previous values will be unavailable:

```lua
pg:query("select 1 as dog, 'hello' as dog") --> { { dog = "hello" } }
```

There is currently no way around this limitation. If this is something you need
then open an [issue](https://github.com/leafo/pgmoon/issues).


## Reference

Functions in table returned by `require("pgmoon")`:

### `new(options={})`

Creates a new `Postgres` object from a configuration object. All fields are
optional unless otherwise stated. The newly created object will not
automatically connect, you must call `conect` after creating the object.

Available options:

* `"database"`: the database name to connect to **required**
* `"host"`: the host to connect to (default: `"127.0.0.1"`)
* `"port"`: the port to connect to (default: `"5432"`)
* `"user"`: the database username to authenticate (default: `"postgres"`)
* `"password"`: password for authentication, may be required depending on server configuration
* `"ssl"`: enable ssl (default: `false`)
* `"ssl_verify"`: verify server certificate (default: `nil`)
* `"ssl_required"`: abort the connection if the server does not support SSL connections (default: `nil`)
* `"socket_type"`: the type of socket to use, one of: `"nginx"`, `"luasocket"`, `cqueues` (default: `"nginx"` if in nginx, `"luasocket"` otherwise)
* `"application_name"`: set the name of the connection as displayed in `pg_stat_activity`. (default: `"pgmoon"`)
* `"pool"`: (OpenResty only) name of pool to use when using OpenResty cosocket (default: `"#{host}:#{port}:#{database}"`)
* `"pool_size"`: (OpenResty only) Passed directly to OpenResty cosocket connect function, [see docs](https://github.com/openresty/lua-nginx-module#tcpsockconnect)
* `"backlog"`: (OpenResty only) Passed directly to OpenResty cosocket connect function, [see docs](https://github.com/openresty/lua-nginx-module#tcpsockconnect)
* `"cqueues_openssl_context"`: Manually created `opensssl.ssl.context` to use when created cqueues SSL connections
* `"luasec_opts"`: Manually created options object to use when using LuaSec SSL connections

Methods on the `Postgres` object returned by `new`:

### `postgres:connect()`

```lua
local success, err = postgres:connect()
```

Connects to the Postgres server using the credentials specified in the call to
`new`. On success returns `true`, on failure returns `nil` and the error
message.

### `postgres:settimeout(time)`

```lua
postgres:settimeout(5000) -- 5 second timeout
```

Sets the timeout value (in milliseconds) for all subsequent socket operations
(connect, write, receive). This function does not have any return values.

The default timeout depends on the underslying socket implementation but
generally corresponds to no timeout.

### `postgres:disconnect()`

```lua
local success, err = postgres:disconnect()
```

Closes the socket. Returns `nil` if the socket couldn't be closed. On most
socket types, `connect` can be called again to reestaablish a connection with
the same postgres object instance.

### `postgres:keepalive(...)`

```lua
postgres:keepalive()
```

Relinquishes socket to OpenResty socket pool via the `setkeepalive` method. Any
arguments passed here are also passed to `setkeepalive`. After calling this
method, the socket is no longer available for queries and should be considered
disconnected.

> Note: This method only works within OpenResty using the nginx cosocket API

### `postgres:query(query_string, ...)`

```lua
-- return values for successful query
local result, err, num_queries = postgres:query("select name from users limit 2")

-- return value for failure (status is nil)
local status, err, partial_result, num_queries = postgres:query("select created_at from tags; select throw_error() from users")
```

Sends a query (or multiple queries) to the server. On failure the first return
value is `nil`, followed by a string describing the error. Since a single call
to `postgres:query` can contain multiple queries, the results of any queries that
succeeded before the error occurred are returned after the error message.
(Note: queries are atomic, they either succeed or fail. The partial result will
only contain succeed queries, not partially data from the failed query)

<details>
<summary>Additional return values: notifications and notices</summary>

---

In addition to the return values above, pgmoon will also return two additional
values if the query generates them, notifications an notices.

```lua
local result, err, num_queries, notifications, notices  = postgres:query("drop table if exists some_table")
```
In this example, if the table `some_table` does not exist, then  `notices` will
be an array containing a message that the table didn't exist.

---

</details>

The query function has two modes of operation which correspond to the two
protocols the Postgres server provides for sending queries to the database
server:

* **Simple protocol**: you only pass in a single argument, the query string
* **Extended protocol**: you pass in a query with parameter placeholders (`$1`, `$2`, etc.) and then pass in additional arguments which will be used as values for the placeholders

See [Extended and simple query protocol](#extended-and-simple-query-protocols)
for more information about the differences and trade-offs.

On success, the result returned depends on the kind of query sent:

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


When using the *simple protocol* (calling the function with a single string),
you can send multiple queries at once by separating them with a `;`. The number
of queries executed is returned as a second return value after the result
object. When more than one query is executed then the result object changes
slightly. It becomes a array table holding all the individual results:

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

### `postgres:escape_literal(val)`

```lua
local sql_fragment = postgres:escape_literal(val)

local res = postgres:query("select created_at from users where id = " .. sql_fragment)
```

Escapes a Lua value int a valid SQL fragment that can be safely concatenated
into a query string. **Never** concatenate a variable into query without
escaping it in some way, or you may open yourself up to [SQL injection
attacks](https://en.wikipedia.org/wiki/SQL_injection).

This function is aware of the following Lua value types:

* `type(val) == "number"` &#8594; `escape_literal(5.5) --> 5.5`
* `type(val) == "string"` &#8594; `escape_literal("your's") --> 'your''s'`
* `type(val) == "boolean"` &#8594; `escape_literal(true) --> TRUE`
* `val == pgmoon.NULL` &#8594; `escape_literal(pgmoon.NULL) --> NULL`

Any other type will throw a hard `error`, to ensure that you provide a value
that is safe for escaping.

### `postgres:escape_identifier(val)`

```lua
local sql_fragment = postgres:escape_identifier(some_table_name)`

local res = postgres:query("select * from " .. sql_fragment .. " limit 20)
```

Escapes a Lua value for use as a Postgres identifier. This includes things like
table or column names. This does not include regular values, you should use
`escape_literal` for that. Identifier escaping is required when names collide
with built in language keywords.

The argument, `val`, must be a string.

### `tostring(postgres)`

```lua
print(tostring(postgres)) --> "<Postgres socket: 0xffffff>"
```

Returns string representation of current state of `Postgres` object.

## Extended and simple query protocols

pgmoon will issue your query to the database server using either the simple or
extended protocol depending if you provide parameters and parameter
placeholders in your query. The simple protocol is used for when your query is
just a string, and the extended protocol is used when you provide addition
parameters as arguments to the `query` method.

The protocols have some trade-offs and differences:

### Extended protocol

```lua
local res, err = postgres:query("select name from users where id = $1 and status = $2", 12, "ready")
```

* **Advantage**: Parameters can be included in query without risk of SQL injection attacks, no need to escape values and interpolate strings
* **Advantage**: Supports the `pgmoon_serialize` method to allow for custom types to be automatically serialized into parameters for the query
* **Disadvantage**: Only a single query can be sent a time
* **Disadvantage**: Substantially more overhead per query. A no-op query may be 50% to 100% slower. (note that this overhead may be negligible depending on the runtime of the query itself)
* **Disadvantage**: Some kinds of query syntax are not compatible with parameters (eg. `where id in (...)`, dynamic expressions), so you may still need to use string interpolation and assume the associated risks

### Simple protocol

```lua
local res, err = postgres:query("select name from users where id = " .. postgres:escape_literal(12) .." and status = " .. postgres:escape_literal("ready"))
```

* **Advantage**: Higher performance. Low overhead per query means more queries can be sent per second, even when manually escaping and interpolating parameters
* **Advantage**: Multiple queries can be sent in a single request (separated by `;`)
* **Disadvantage**: Any parameters to the query must be manually escaped and interpolated into the query string. This can be error prone and introduce SQL injection attacks if not done correctly

> Note: The extended protocol also supports binary encoding of parameter values
> & results, but since Lua treats binary as strings, it's generally going to be
> faster to just consume the string values from Postgres rather than using the
> binary protocol which will require binary to string conversion within Lua.

## SSL connections

pgmoon can establish an SSL connection to a Postgres server. It can also refuse
to connect to it if the server does not support SSL. Just as pgmoon depends on
LuaSocket for usage outside of OpenResty, it depends on luaossl/LuaSec for SSL
connections in such contexts.

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new({
  host = "127.0.0.1",
  ssl = true, -- enable SSL
  ssl_verify = true, -- verify server certificate
  ssl_required = true, -- abort if the server does not support SSL connections
  ssl_version = "tlsv1_2", -- e.g., defaults to highest available, no less than TLS v1.1
  cafile = "...", -- certificate authority (LuaSec only)
  cert = "...", -- client certificate
  key = "...", -- client key
})

assert(pg:connect())
```

> **Note:** In Postgres 12 and above, the minium SSL version accepted by client
> connections is 1.2. When using LuaSocket + LuaSec to connect to an SSL
> server, if you don't specify an `ssl_version` then `tlsv1_2` is used.

In OpenResty, make sure to configure the
[lua_ssl_trusted_certificate](https://github.com/openresty/lua-nginx-module#lua_ssl_trusted_certificate)
directive if you wish to verify the server certificate.

## Authentication types

Postgres has a handful of authentication types. pgmoon currently supports
trust, peer and password authentication with scram-sha-256-auth or md5.

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

Arrays are automatically deserialized into a Lua object when they are returned
from a query. Numeric, string, and boolean types are automatically loaded
accordingly. Nested arrays are also supported.

Use `encode_array` to encode a Lua table to array syntax for a query:

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
pg:connect()

local encode_array = require("pgmoon.arrays").encode_array
local my_array = {1,2,3,4,5}
pg:query("insert into some_table (some_arr_col) values(" .. encode_array(my_array) .. ")")
```

Arrays that are returned from queries have their metatable configured for the
`PostgresArray` type (defined in `require("pgmoon.arrays")`).


### Extended protocol

When using the extended query protocol (query with parameters), an array object
created with `PostgresArray` will automatically be serialized when passed as a
parameter.

```lua
local PostgresArray = require("pgmoon.arrays").PostgresArray

postgres:query("update user set tags = $1 where id = 44", PostgresArray({1,2,4}))
```

Keep in mind that calling `PostgresArray` mutate the argument by setting its
metatable. Make a copy first if you don't want the original object to be
mutated.

Additionally, array types must contain values of only the same type. No
run-time checking is performed on the object you pass. The type OID is
determined from the first entry of the array.

### Empty Arrays

When trying to encode an empty array an error will be thrown. Postgres requires
a type when using an array. When there are values in the array Postgres can
infer the type, but with no values in the array no type can be inferred. This
is illustrated in the erorr provided by Postgres:


```
postgres=# select ARRAY[];
ERROR:  cannot determine type of empty array
LINE 1: select ARRAY[];
               ^
HINT:  Explicitly cast to the desired type, for example ARRAY[]::integer[].
```

You can work around this error by always including a typecast with any value
you use, to allow you to pass in an empty array and continue to work with an
array of values assuming the types match.

```lua
local empty_tags = {}
pg:query("update posts set tags = " .. encode_array(empty_tags) .. "::text[]")
```

## Handling JSON

`json` and `jsonb` values are automatically decoded as Lua tables in a query
result (using the `cjson` library if available).

To send JSON in a query you must first convert it into a string literal, then
interpolate it into your query. Ensure that you treat it like any other
paramter, and call `escape_literal` on the string to make it suitable to be
safely parsed as a value to PostgreSQL.

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(auth)
assert(pg:connect())

local my_tbl = { hello = "world" }

local json = require "cjson"

pg:query("update my_table set data = " .. db.escape_literal(json.encode(my_tbl)) .. " where id = 124"
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

Use `encode_hstore` to encode a Lua table into hstore syntax suitable for
interpolating into a query.

> Note: The result of `encode_hstore` is a valid Postgres SQL fragment, it is
> not necessary to call escape_literal on it. It can safely be inserted
> directly into the query

```lua
local encode_hstore = require("pgmoon.hstore").encode_hstore
local tbl = {foo = "bar"}
pg:query("insert into some_table (hstore_col) values(" .. encode_hstore(tbl) .. ")")
```

You can manually decode a hstore value from string using the `decode_hstore`
function. This is only required if you didn't call `setup_hstore`.

```lua
local decode_hstore = require("pgmoon.hstore").decode_hstore
local res = pg:query("select * from some_table")
local hstore_tbl = decode_hstore(res[1].hstore_col)
```

## Custom type deserializer

PostgreSQL has a rich set of types. When reading a query's results pgmoon must
attempt to interpret the types from postgres and map them to something usable
in Lua. By default implementations are included for primitives like numbers,
booleans, strings, and JSON.

You can provie you own type deserializer if you want to add custom behavior for
certain types of values returned by PostgreSQL.

You must have some knowledge of types and type OIDs. Every type in PostgreSQL
is stored in the `pg_type` catalog table. Each type has an OID (stored as a 32
bit positive integer) to uniquely identify it. The core types provided by
Postgres have fixed type OIDs (for example, boolean is always 16), but
third-party types may be added without fixed OIDs.

Also note that any composite versions of existing types have their own OID, for
example, while a single boolean value has type OID 16, an array of boolean
values has type OID 1000. Arrays are homogeneous and must contain the same type
for every value.

Adding support for a new type in pgmoon can be done using the
`set_type_deserializer(oid, type_name, [deserializer])` method:

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new(config)

-- in this example we create a new deserializer called bignumber and provide
-- the function to deserialize (type OID 20 is an 8 byte integer)
pg:set_type_deserializer(20, "bignumber", function(val)
    return "HUGENUMBER:" .. val
end)

-- in this example we point another OID to the "bignumber" deserializer we
-- provided above (type OID 701 is a 8 byte floating point number)
pg:set_type_deserializer(701, "bignumber")
```

The arguments are as follows:

* `oid` The OID from `pg_type` that will be handled
* `name` The local name of the type. This is a name that points to an existing deserializer or will be used to register a new one if the `deserializer` argument is 
* `deserializer` A function that takes the raw string value from Postgres and converts it into something more useful (optional). Any existing deserializer function with the same name will be overwritten

## Custom type serializer

When using the query method with params, (aka the extended query protocol), and
values passed into parameters must be serialized into a string version of that
value and a type OID.

pgmoon provides implementations for Lua's basic types: string, boolean,
numbers, and `postgres.NULL` for the `NULL` value.

If you want to support custom types, like JSON, then you will need to provide
your own serializer.

> Serializing vs escaping: pgmoon has two methods for preparing data to be sent
> in a query. *Escaping* is used when you want to turn some value into a SQL
> fragment that can be safely concatenated into a query. This is done with
> `postgres:escape_literal()` and is suitable for use with the simple query
> protocol. *Serializing*, on the other hand, is used to convert a value into a
> string representation that can be parsed by Postgres as a value when using
> the extended query protocol. As an example, an *escaped* string would be
> `'hello'` (notice the quotes, this is a fragment of valid SQL syntax, whereas
> a serialized string would be just the string: `hello` (and typically paired
> with a type OID, typically `25` for text). Serializing is the oposite of
> deserializing, which is described above.


> **Note:** Serializing is **NOT** the same as escaping. You can not take a
> serialized value and concatenate it directly into your query. You may,
> however, take a serialized value and escape it as a string, then attempt to
> cast it to the appropriate type within your query.


To provide your own serializer for an object, you can add a method on the
metatable called `pgmoon_serialize`. This method takes two arguments, the value
to be serialized and the current instance of `Postgres` that is doing the
serialization. The method should return two values: the type OID as an integer,
and the string representation of that value.

> Note: The type OID 0 can be used for "unknown", and Postgres will try to
> infer the type of the value based on the context. If possible you should
> always try to provide a specific type OID.

```lua
-- this metatable will enable an object to be serialized as json for use as a
-- parameter in postgres:query()
local json_mt = {
  pgmoon_serialize = function(v)
    local cjson = require("cjson")
    return 114, cjson.encode(v) -- 114 is oid from pg_type catalog
  end
}

local data = {
  age = 200,
  color = "blue",
  tags = {"one", "two"}
}

postgres:query("update user set data = $1 where id = 233", setmetatable(data, json_mt))
```

The `pgmoon_serialize` method can also return `nil` and an error message to
abort serialization. This will block the query from running at all, and the
error will be returned from the `postgres:query()` method.

> Note: Postgres supports a binary representation for values when using the
> extended query protocol, but at this time pgmoon does not support it.


## Converting `NULL`s

By default `NULL`s in Postgres are converted to `nil`, meaning they aren't
visible in the resulting tables. If you want to convert `NULL`s to some visible
value set `convert_null` to `true` on the `Postgres` object and the
`postgres.NULL` object will be used to represent NULL.

```lua
local pgmoon = require("pgmoon")
local config = {
  database = "my_database",
  convert_null = true
}

local postgres = pgmoon.new(config)
assert(postgres:connect())

local res = postgres:query("select NULL the_null")
assert(postgres.NULL == res[1].the_null)
```

As shown above, the `NULL` value is set to `postgres.NULL`. It's possible to change
this value to make pgmoon use something else as `NULL`. For example if you're
using OpenResty you might want to reuse `ngx.null`.

Also note that you can use `postgres.NULL` as an extended query parameter or
inside `escape_literal` to generate the value for `NULL`.

# Contact

Author: Leaf Corcoran (leafo) ([@moonscript](http://twitter.com/moonscript))
Email: leafot@gmail.com
Homepage: <http://leafo.net>


# Changelog

Note: Future changenotes will be published on GitHub releases page: https://github.com/leafo/pgmoon/releases

* 1.15.0 — 2022-6-3 - Extended query protocol
* 1.14.0 — 2022-2-17 - OpenResty crypto functions used, better empty array support, 
* 1.13.0 — 2021-10-13 - Add support for scram_sha_256_auth (@murillopaula), 'backlog' and 'pool_size' options while using ngx.socket (@xiaocang), update LuaSec ssl_protocol default options (@jeremymv2), `application_name` option (@mecampbellsoup)
* 1.12.0 — 2021-01-06 - Lua pattern compatibility fix, Support for Lua 5.1 through 5.4 (@jprjr). Fix bug where SSL vesrion was not being passed. Default to TLS v1.2 when using LuaSec. Luabitop is no longer automatically installed as a dependency. New test suite.
* 1.11.0 — 2020-03-26 - Allow for TLS v1.2 when using LuaSec (Miles Elam)
* 1.10.0 — 2019-04-15 - Support luaossl for crypto functions, added better error when missing crypto library
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

Copyright (C) 2021 by Leaf Corcoran

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

  [luaossl]: https://github.com/wahern/luaossl
  [LuaCrypto]: https://luarocks.org/modules/starius/luacrypto
  [LuaSec]: https://github.com/brunoos/luasec
  [Lapis]: http://leafo.net/lapis
  [OpenResty]: https://openresty.org/
  [LuaSocket]: http://w3.impa.br/~diego/software/luasocket/
  [cqueues]: http://25thandclement.com/~william/projects/cqueues.html
