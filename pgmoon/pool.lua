local Postgres
Postgres = require("pgmoon").Postgres
local PostgresPool
do
  local _class_0
  local _base_0 = {
    NULL = Postgres.NULL,
    PG_TYPES = Postgres.PG_TYPES,
    type_deserializers = Postgres.type_deserializers,
    _get_connection = function(self)
      if #self.pool == 0 then
        return nil, "not connected"
      end
      local _list_0 = self.pool
      for _index_0 = 1, #_list_0 do
        local pg = _list_0[_index_0]
        if not (pg.busy) then
          return pg
        end
      end
      if self.config.max_pool_size and #self.pool >= self.config.max_pool_size then
        return nil, "pool exhausted, max_pool_size reached"
      end
      local pg = self:_create_instance()
      local ok, err = pg:connect()
      if not (ok) then
        return nil, err
      end
      table.insert(self.pool, pg)
      return pg
    end,
    _create_instance = function(self)
      local pg_config
      do
        local _tbl_0 = { }
        for k, v in pairs(self.config) do
          if k ~= "max_pool_size" then
            _tbl_0[k] = v
          end
        end
        pg_config = _tbl_0
      end
      local pg = Postgres(pg_config)
      pg.PG_TYPES = self.PG_TYPES
      pg.type_deserializers = self.type_deserializers
      pg.parent_pool = self
      if self._timeout then
        pg:settimeout(self._timeout)
      end
      return pg
    end,
    connect = function(self)
      if #self.pool > 0 then
        return nil, "already connected"
      end
      local pg = self:_create_instance()
      local ok, err = pg:connect()
      if not (ok) then
        return nil, err
      end
      table.insert(self.pool, pg)
      return true
    end,
    disconnect = function(self)
      local _list_0 = self.pool
      for _index_0 = 1, #_list_0 do
        local pg = _list_0[_index_0]
        pg:disconnect()
      end
      self.pool = { }
      return true
    end,
    keepalive = function(self, ...)
      local _list_0 = self.pool
      for _index_0 = 1, #_list_0 do
        local pg = _list_0[_index_0]
        pg:keepalive(...)
      end
      self.pool = { }
      return true
    end,
    settimeout = function(self, ...)
      self._timeout = ...
      local _list_0 = self.pool
      for _index_0 = 1, #_list_0 do
        local pg = _list_0[_index_0]
        pg:settimeout(...)
      end
    end,
    set_type_deserializer = function(self, ...)
      Postgres.set_type_deserializer(self, ...)
      local _list_0 = self.pool
      for _index_0 = 1, #_list_0 do
        local pg = _list_0[_index_0]
        pg.PG_TYPES = self.PG_TYPES
        pg.type_deserializers = self.type_deserializers
      end
    end,
    query = function(self, ...)
      local pg, err = self:_get_connection()
      if not (pg) then
        return nil, err
      end
      return pg:query(...)
    end,
    simple_query = function(self, q)
      local pg, err = self:_get_connection()
      if not (pg) then
        return nil, err
      end
      return pg:simple_query(q)
    end,
    extended_query = function(self, ...)
      local pg, err = self:_get_connection()
      if not (pg) then
        return nil, err
      end
      return pg:extended_query(...)
    end,
    wait_for_notification = function(self)
      return error("can't use wait for notification with pool")
    end,
    escape_identifier = Postgres.escape_identifier,
    escape_literal = Postgres.escape_literal,
    encode_bytea = Postgres.encode_bytea,
    decode_bytea = Postgres.decode_bytea,
    setup_hstore = Postgres.setup_hstore,
    pool_size = function(self)
      return #self.pool
    end,
    active_connections = function(self)
      local count = 0
      local _list_0 = self.pool
      for _index_0 = 1, #_list_0 do
        local pg = _list_0[_index_0]
        if pg.busy then
          count = count + 1
        end
      end
      return count
    end,
    __tostring = function(self)
      return "<PostgresPool size: " .. tostring(self:pool_size()) .. ">"
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, config)
      if config == nil then
        config = { }
      end
      self.config = config
      self.pool = { }
      self._timeout = nil
      self.convert_null = self.config.convert_null or false
    end,
    __base = _base_0,
    __name = "PostgresPool"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  PostgresPool = _class_0
end
return {
  PostgresPool = PostgresPool,
  new = PostgresPool
}
