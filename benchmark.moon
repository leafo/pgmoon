-- pgmoon query benchmark harness
--
-- Runs a set of workloads against a live PostgreSQL server and reports
-- timing, allocation pressure, and socket receive calls per query. Each
-- workload is run in two modes (optimized vs legacy result parsing, where
-- legacy is a snapshot of the pre-optimization parse functions) with
-- repetitions interleaved between the modes so system load drift affects
-- both equally.
--
-- usage:
--   resty benchmark.lua   -- nginx cosocket implementation
--   luajit benchmark.lua  -- luasocket implementation
--
-- config via environment:
--   PGMOON_HOST (127.0.0.1), PGMOON_PORT (5432), PGMOON_USER (postgres),
--   PGMOON_PASSWORD, PGMOON_DATABASE (postgres)

import Postgres from require "pgmoon"

HOST = os.getenv("PGMOON_HOST") or "127.0.0.1"
PORT = os.getenv("PGMOON_PORT") or "5432"
USER = os.getenv("PGMOON_USER") or "postgres"
PASSWORD = os.getenv("PGMOON_PASSWORD")
DATABASE = os.getenv("PGMOON_DATABASE") or "postgres"

REPS = 7 -- timed repetitions per workload per mode, median is reported

gettime = do
  ok, socket = pcall require, "socket"
  if ok and socket.gettime
    socket.gettime
  elseif ngx
    ->
      ngx.update_time!
      ngx.now!
  else
    error "no suitable clock available (need luasocket or ngx)"

-- methods proxied with call counting. receiveany may not exist on every
-- socket implementation
SOCKET_METHODS = {
  "connect", "send", "receive", "receiveany", "settimeout"
  "getreusedtimes", "setkeepalive", "close", "sslhandshake"
}

-- replace pg.sock with a counting proxy. must be called before connect
instrument_socket = (pg, counters) ->
  real = pg.sock

  proxy = {}
  for name in *SOCKET_METHODS
    fn = real[name]
    continue unless fn
    proxy[name] = do
      _name, _fn = name, fn
      (_, ...) ->
        counters[_name] = (counters[_name] or 0) + 1
        _fn real, ...

  setmetatable proxy, {
    __index: (t, key) -> real[key]
    __tostring: -> tostring real
  }

  pg.sock = proxy

-- snapshot of the result parsing implementation before the parse path was
-- optimized (per-column converters, byte arithmetic), used as the baseline
-- mode for comparison
legacy_parse_row_desc = (row_desc) =>
  num_fields = @decode_int row_desc\sub(1,2)
  offset = 3
  fields = for i=1,num_fields
    name = row_desc\match "[^%z]+", offset
    offset += #name + 1

    data_type = @decode_int row_desc\sub offset + 6, offset + 6 + 3
    data_type = @PG_TYPES[data_type] or "string"

    format = @decode_int row_desc\sub offset + 16, offset + 16 + 1
    assert 0 == format, "don't know how to handle format"

    offset += 18
    {name, data_type}

  fields

legacy_parse_data_row = (data_row, fields) =>
  num_fields = @decode_int data_row\sub(1,2)
  out = {}

  offset = 3
  for i=1,num_fields
    field = fields[i]
    continue unless field
    {field_name, field_type} = field

    len = @decode_int data_row\sub offset, offset + 3
    offset += 4

    if len < 0
      out[field_name] = @NULL if @convert_null
      continue

    value = data_row\sub offset, offset + len - 1
    offset += len

    switch field_type
      when "number"
        value = tonumber value
      when "boolean"
        value = value == "t"
      when "string"
        nil
      else
        if fn = @type_deserializers[field_type]
          value = fn @, value, field_type

    out[field_name] = value

  out

connect = (mode) ->
  config = {
    socket_type: ngx and "nginx" or "luasocket"
    host: HOST
    port: PORT
    user: USER
    password: PASSWORD
    database: DATABASE
  }

  pg = Postgres config
  counters = {}
  instrument_socket pg, counters

  if mode and mode.patch
    mode.patch pg

  assert pg\connect!
  pg, counters

setup_tables = (pg) ->
  assert pg\simple_query "drop table if exists pgmoon_bench"
  assert pg\simple_query "create unlogged table pgmoon_bench as
    select i as id,
      i % 2 = 0 as flag,
      i * 7 as count,
      'name-' || i as name,
      repeat('payload-', 12) || i as blob
    from generate_series(1, 5000) i"

  assert pg\simple_query "drop table if exists pgmoon_bench_wide"
  assert pg\simple_query "create unlogged table pgmoon_bench_wide as
    select i as id, repeat('x', 8192) as blob
    from generate_series(1, 50) i"

  assert pg\simple_query "drop table if exists pgmoon_bench_numeric"
  assert pg\simple_query "create unlogged table pgmoon_bench_numeric as
    select i as a, i * 2 as b, i * 3 as c,
      i / 2.5 as d, i * 1.5 as e,
      i + 7 as f, i % 100 as g, i * i as h
    from generate_series(1, 1000) i"

-- n: timed iterations per rep, rows: expected rows per query (for rows/s)
WORKLOADS = {
  {
    name: "tiny_select"
    n: 2000
    rows: 1
    exec: (pg) -> assert pg\simple_query "select 1 as a, 'hello' as b"
  }
  {
    name: "extended_params"
    n: 2000
    rows: 1
    exec: (pg) -> assert pg\extended_query "select $1 + $2 as sum, $3 as name", 5, 7, "hello"
  }
  {
    name: "rows_100"
    n: 500
    rows: 100
    exec: (pg) -> assert pg\simple_query "select * from pgmoon_bench limit 100"
  }
  {
    name: "rows_5000"
    n: 50
    rows: 5000
    exec: (pg) -> assert pg\simple_query "select * from pgmoon_bench"
  }
  {
    name: "numeric_8col"
    n: 200
    rows: 1000
    exec: (pg) -> assert pg\simple_query "select * from pgmoon_bench_numeric"
  }
  {
    name: "rows_5000_array"
    n: 50
    rows: 5000
    optimized_only: true
    exec: (pg) -> assert pg\query_array "select * from pgmoon_bench"
  }
  {
    name: "numeric_8col_arr"
    n: 200
    rows: 1000
    optimized_only: true
    exec: (pg) -> assert pg\query_array "select * from pgmoon_bench_numeric"
  }
  {
    name: "wide_text_50"
    n: 200
    rows: 50
    exec: (pg) -> assert pg\simple_query "select blob from pgmoon_bench_wide"
  }
  {
    name: "big_value_1mb"
    n: 30
    rows: 1
    exec: (pg) -> assert pg\simple_query "select repeat('x', 1024*1024) as v"
  }
}

MODES = {
  { name: "optimized" }
  {
    name: "legacy"
    patch: (pg) ->
      pg.parse_row_desc = legacy_parse_row_desc
      pg.parse_data_row = legacy_parse_data_row
  }
}

median = (times) ->
  table.sort times
  times[math.ceil #times / 2]

-- run one workload in all applicable modes with reps interleaved across modes
run_workload = (w, connections) ->
  -- workloads that use interfaces the legacy patch doesn't support only run
  -- against the unpatched implementation
  modes = if w.optimized_only
    [m for m in *MODES when not m.patch]
  else
    MODES

  -- warmup
  for mode in *modes
    pg = connections[mode.name].pg
    for i=1, math.max 3, math.floor w.n / 10
      w.exec pg

  times = {mode.name, {} for mode in *modes}

  for r=1, REPS
    for mode in *modes
      pg = connections[mode.name].pg
      start = gettime!
      for i=1, w.n
        w.exec pg
      table.insert times[mode.name], gettime! - start

  results = {}

  for mode in *modes
    {:pg, :counters} = connections[mode.name]

    -- allocation pressure: bytes allocated per query with the collector paused
    collectgarbage "collect"
    collectgarbage "stop"
    alloc_n = math.min w.n, 50
    before = collectgarbage "count"
    for i=1, alloc_n
      w.exec pg
    alloc_kb = (collectgarbage("count") - before) / alloc_n
    collectgarbage "restart"

    -- socket receive calls per query, measured over a dedicated pass
    for k in pairs counters
      counters[k] = nil

    count_n = math.min w.n, 100
    for i=1, count_n
      w.exec pg

    median_time = median times[mode.name]

    results[mode.name] = {
      name: w.name
      n: w.n
      median: median_time
      qps: w.n / median_time
      rps: w.n * w.rows / median_time
      alloc_kb: alloc_kb
      recv_per_query: ((counters.receive or 0) + (counters.receiveany or 0)) / count_n
    }

  results

header = "%-16s %-11s %6s %10s %11s %12s %10s %8s"\format "workload", "mode", "n", "median_s", "queries/s", "rows/s", "KB/query", "recv/q"

row_fmt = (r, mode_name) ->
  "%-16s %-11s %6d %10.4f %11.1f %12.1f %10.2f %8.2f"\format r.name, mode_name, r.n, r.median, r.qps, r.rps, r.alloc_kb, r.recv_per_query

do
  pg = connect!
  print "Server: #{HOST}:#{PORT} db=#{DATABASE}"
  print "Socket type: #{pg.sock_type}, pgmoon #{require("pgmoon").VERSION}, #{jit and jit.version or _VERSION}"
  setup_tables pg
  pg\disconnect!

connections = {}
for mode in *MODES
  pg, counters = connect mode
  connections[mode.name] = {:pg, :counters}

print!
print header

for w in *WORKLOADS
  results = run_workload w, connections

  for mode in *MODES
    if r = results[mode.name]
      print row_fmt r, mode.name

  optimized = results.optimized
  legacy = results.legacy
  if optimized and legacy and optimized.median > 0
    print "%-16s %-11s speedup: %0.2fx, alloc: %0.2f -> %0.2f KB/query"\format "", "", legacy.median / optimized.median, legacy.alloc_kb, optimized.alloc_kb

for mode in *MODES
  connections[mode.name].pg\disconnect!
