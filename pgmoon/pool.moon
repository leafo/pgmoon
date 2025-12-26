import Postgres from require "pgmoon"

class PostgresPool
  NULL: Postgres.NULL
  PG_TYPES: Postgres.PG_TYPES
  type_deserializers: Postgres.type_deserializers

  new: (@config={}) =>
    @pool = {}
    @_timeout = nil
    @convert_null = @config.convert_null or false

  _get_connection: =>
    -- Must call connect() first
    return nil, "not connected" if #@pool == 0

    -- Find first non-busy instance
    for pg in *@pool
      unless pg.busy
        return pg

    -- All busy, check max_pool_size
    if @config.max_pool_size and #@pool >= @config.max_pool_size
      return nil, "pool exhausted, max_pool_size reached"

    -- Create and connect new instance
    pg = @_create_instance!
    ok, err = pg\connect!
    return nil, err unless ok

    table.insert @pool, pg
    pg

  _create_instance: =>
    -- Filter out pool-specific config keys
    pg_config = {k, v for k, v in pairs @config when k != "max_pool_size"}
    pg = Postgres pg_config

    -- Apply stored settings
    pg.PG_TYPES = @PG_TYPES
    pg.type_deserializers = @type_deserializers
    pg.parent_pool = @
    pg\settimeout @_timeout if @_timeout

    pg

  -- Connection lifecycle
  connect: =>
    return nil, "already connected" if #@pool > 0
    pg = @_create_instance!
    ok, err = pg\connect!
    return nil, err unless ok
    table.insert @pool, pg
    true

  disconnect: =>
    for pg in *@pool
      pg\disconnect!
    @pool = {}
    true

  keepalive: (...) =>
    for pg in *@pool
      pg\keepalive ...
    @pool = {}
    true

  -- Settings (apply to all existing + store for new)
  settimeout: (...) =>
    @_timeout = ...
    for pg in *@pool
      pg\settimeout ...

  set_type_deserializer: (...) =>
    Postgres.set_type_deserializer @, ...

    -- ensure all collections point to the pools type table
    for pg in *@pool
      pg.PG_TYPES = @PG_TYPES
      pg.type_deserializers = @type_deserializers

  -- Query methods (delegate to available connection)
  query: (...) =>
    pg, err = @_get_connection!
    return nil, err unless pg
    pg\query ...

  simple_query: (q) =>
    pg, err = @_get_connection!
    return nil, err unless pg
    pg\simple_query q

  extended_query: (...) =>
    pg, err = @_get_connection!
    return nil, err unless pg
    pg\extended_query ...

  -- wait_for_notification is tied to the socket connection that issued the
  -- `LISTEN` query, so it's not compatible with pooling
  wait_for_notification: =>
    error "can't use wait for notification with pool"

  -- Static methods (delegate to Postgres)
  -- note the reciever will be the pool object
  escape_identifier: Postgres.escape_identifier
  escape_literal: Postgres.escape_literal
  encode_bytea: Postgres.encode_bytea
  decode_bytea: Postgres.decode_bytea
  setup_hstore: Postgres.setup_hstore

  -- Pool info helpers
  pool_size: => #@pool
  active_connections: =>
    count = 0
    for pg in *@pool
      if pg.busy
        count += 1
    count

  __tostring: =>
    "<PostgresPool size: #{@pool_size!}>"

{ :PostgresPool, new: PostgresPool }
