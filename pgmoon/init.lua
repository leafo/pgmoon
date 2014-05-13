local insert
do
  local _obj_0 = table
  insert = _obj_0.insert
end
local tcp
do
  local _obj_0 = require("pgmoon.socket")
  tcp = _obj_0.tcp
end
local _len
_len = function(thing, t)
  if t == nil then
    t = type(thing)
  end
  local _exp_0 = t
  if "string" == _exp_0 then
    return #thing
  elseif "table" == _exp_0 then
    local l = 0
    for _index_0 = 1, #thing do
      local inner = thing[_index_0]
      local inner_t = type(inner)
      if inner_t == "string" then
        l = l + #inner
      else
        l = l + _len(inner, inner_t)
      end
    end
    return l
  else
    return error("don't know how to calculate length of " .. tostring(t))
  end
end
local _debug_msg
_debug_msg = function(str)
  return require("moon").dump((function()
    local _accum_0 = { }
    local _len_0 = 1
    for p in str:gmatch("[^%z]+") do
      _accum_0[_len_0] = p
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end)())
end
local flipped
flipped = function(t)
  local keys
  do
    local _accum_0 = { }
    local _len_0 = 1
    for k in pairs(t) do
      _accum_0[_len_0] = k
      _len_0 = _len_0 + 1
    end
    keys = _accum_0
  end
  for _index_0 = 1, #keys do
    local key = keys[_index_0]
    t[t[key]] = key
  end
  return t
end
local Postgres
do
  local TYPE, ERROR_TYPES, PG_TYPES, NULL, rshift, lshift, band
  local _base_0 = {
    NULL = {
      "NULL"
    },
    convert_null = false,
    connect = function(self)
      self.sock = tcp()
      local ok, err = self.sock:connect(self.host, self.port)
      if not (ok) then
        return nil, err
      end
      if self.sock:getreusedtimes() == 0 then
        local success
        success, err = self:send_startup_message()
        if not (success) then
          return nil, err
        end
        self:auth()
        self:wait_until_ready()
      end
      return true
    end,
    disconnect = function(self)
      local sock = self.sock
      self.sock = nil
      return sock:close()
    end,
    keepalive = function(self, ...)
      local sock = self.sock
      self.sock = nil
      return sock:setkeepalive(...)
    end,
    auth = function(self)
      local t, msg = self:receive_message()
      if TYPE.auth_ok == t then
        return true
      end
      self:disconnect()
      return error("don't know how to auth " .. tostring(t))
    end,
    query = function(self, q)
      self:send_message(TYPE.query, {
        q,
        NULL
      })
      local row_desc, data_rows, command_complete
      while true do
        local t, msg = self:receive_message()
        local _exp_0 = t
        if TYPE.data_row == _exp_0 then
          data_rows = data_rows or { }
          insert(data_rows, msg)
        elseif TYPE.row_description == _exp_0 then
          row_desc = msg
        elseif TYPE.error == _exp_0 then
          error(self:parse_error(msg))
        elseif TYPE.command_complete == _exp_0 then
          command_complete = msg
        elseif TYPE.ready_for_query == _exp_0 then
          break
        end
      end
      local command, affected_rows
      if command_complete then
        command = command_complete:match("^%w+")
        affected_rows = tonumber(command_complete:match("%d+%z$"))
      end
      if row_desc then
        if not (data_rows) then
          return { }
        end
        local fields = self:parse_row_desc(row_desc)
        local num_rows = #data_rows
        for i = 1, num_rows do
          data_rows[i] = self:parse_data_row(data_rows[i], fields)
        end
        if affected_rows and command ~= "SELECT" then
          data_rows.affected_rows = affected_rows
        end
        return data_rows
      end
      if affected_rows then
        return {
          affected_rows = affected_rows
        }
      else
        return true
      end
    end,
    parse_error = function(self, err_msg)
      local severity, message, detail, position
      local offset = 1
      while offset <= #err_msg do
        local t = err_msg:sub(offset, offset)
        local str = err_msg:match("[^%z]+", offset + 1)
        if not (str) then
          break
        end
        offset = offset + (2 + #str)
        local _exp_0 = t
        if ERROR_TYPES.severity == _exp_0 then
          severity = str
        elseif ERROR_TYPES.message == _exp_0 then
          message = str
        elseif ERROR_TYPES.position == _exp_0 then
          position = str
        elseif ERROR_TYPES.detail == _exp_0 then
          detail = str
        end
      end
      local msg = tostring(severity) .. ": " .. tostring(message)
      if position then
        msg = tostring(msg) .. " (" .. tostring(position) .. ")"
      end
      if detail then
        msg = tostring(msg) .. "\n" .. tostring(detail)
      end
      return msg
    end,
    parse_row_desc = function(self, row_desc)
      local num_fields = self:decode_int(row_desc:sub(1, 2))
      local offset = 3
      local fields
      do
        local _accum_0 = { }
        local _len_0 = 1
        for i = 1, num_fields do
          local name = row_desc:match("[^%z]+", offset)
          offset = offset + #name + 1
          local data_type = self:decode_int(row_desc:sub(offset + 6, offset + 6 + 3))
          data_type = PG_TYPES[data_type] or "string"
          local format = self:decode_int(row_desc:sub(offset + 16, offset + 16 + 1))
          assert(0 == format, "don't know how to handle format")
          offset = offset + 18
          local _value_0 = {
            name,
            data_type
          }
          _accum_0[_len_0] = _value_0
          _len_0 = _len_0 + 1
        end
        fields = _accum_0
      end
      return fields
    end,
    parse_data_row = function(self, data_row, fields)
      local num_fields = self:decode_int(data_row:sub(1, 2))
      local out = { }
      local offset = 3
      for i = 1, num_fields do
        local _continue_0 = false
        repeat
          local field = fields[i]
          if not (field) then
            _continue_0 = true
            break
          end
          local field_name, field_type
          field_name, field_type = field[1], field[2]
          local len = self:decode_int(data_row:sub(offset, offset + 3))
          offset = offset + 4
          if len < 0 then
            if self.convert_null then
              out[field_name] = self.NULL
            end
            _continue_0 = true
            break
          end
          local value = data_row:sub(offset, offset + len - 1)
          offset = offset + len
          local _exp_0 = field_type
          if "number" == _exp_0 then
            value = tonumber(value)
          elseif "boolean" == _exp_0 then
            value = value == "t"
          end
          out[field_name] = value
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return out
    end,
    wait_until_ready = function(self)
      while true do
        local t, msg = self:receive_message()
        if TYPE.error == t then
          self:disconnect()
          error(self:parse_error(msg))
        end
        if TYPE.ready_for_query == t then
          break
        end
      end
    end,
    receive_message = function(self)
      local t, err = self.sock:receive(1)
      if not (t) then
        return nil, "failed to get type: " .. tostring(err)
      end
      local len
      len, err = self.sock:receive(4)
      if not (len) then
        return nil, "failed to get len: " .. tostring(err)
      end
      len = self:decode_int(len)
      len = len - 4
      local msg = self.sock:receive(len)
      return t, msg
    end,
    send_startup_message = function(self)
      assert(self.user, "missing user for connect")
      assert(self.db, "missing database for connect")
      local data = {
        self:encode_int(196608),
        "user",
        NULL,
        self.user,
        NULL,
        "database",
        NULL,
        self.db,
        NULL,
        NULL
      }
      return self.sock:send({
        self:encode_int(_len(data) + 4),
        data
      })
    end,
    send_message = function(self, t, data, len)
      if len == nil then
        len = nil
      end
      if len == nil then
        len = _len(data)
      end
      len = len + 4
      return self.sock:send({
        t,
        self:encode_int(len),
        data
      })
    end,
    decode_int = function(self, str, bytes)
      if bytes == nil then
        bytes = #str
      end
      local _exp_0 = bytes
      if 4 == _exp_0 then
        local d, c, b, a = str:byte(1, 4)
        return a + lshift(b, 8) + lshift(c, 16) + lshift(d, 24)
      elseif 2 == _exp_0 then
        local b, a = str:byte(1, 2)
        return a + lshift(b, 8)
      else
        return error("don't know how to decode " .. tostring(bytes) .. " byte(s)")
      end
    end,
    encode_int = function(self, n, bytes)
      if bytes == nil then
        bytes = 4
      end
      local _exp_0 = bytes
      if 4 == _exp_0 then
        local a = band(n, 0xff)
        local b = band(rshift(n, 8), 0xff)
        local c = band(rshift(n, 16), 0xff)
        local d = band(rshift(n, 24), 0xff)
        return string.char(d, c, b, a)
      else
        return error("don't know how to encode " .. tostring(bytes) .. " byte(s)")
      end
    end,
    escape_identifier = function(self, ident)
      return '"' .. (tostring(ident):gsub('"', '""')) .. '"'
    end,
    escape_literal = function(self, val)
      local _exp_0 = type(val)
      if "number" == _exp_0 then
        return tostring(val)
      elseif "string" == _exp_0 then
        return "'" .. tostring((val:gsub("'", "''"))) .. "'"
      elseif "boolean" == _exp_0 then
        return val and "TRUE" or "FALSE"
      end
      return error("don't know how to escape value: " .. tostring(val))
    end,
    __tostring = function(self)
      return "<Postgres socket: " .. tostring(self.sock) .. ">"
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function(self, user, db, host, port)
      if user == nil then
        user = "postgres"
      end
      if host == nil then
        host = "127.0.0.1"
      end
      if port == nil then
        port = "5432"
      end
      self.user, self.db, self.host, self.port = user, db, host, port
    end,
    __base = _base_0,
    __name = "Postgres"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  local self = _class_0
  TYPE = flipped({
    status = "S",
    auth_ok = "R",
    backend_key = "K",
    ready_for_query = "Z",
    query = "Q",
    notice = "N",
    row_description = "T",
    data_row = "D",
    command_complete = "C",
    error = "E"
  })
  ERROR_TYPES = flipped({
    severity = "S",
    code = "C",
    message = "M",
    position = "P",
    detail = "D"
  })
  PG_TYPES = {
    [16] = "boolean",
    [20] = "number",
    [21] = "number",
    [23] = "number",
    [700] = "number",
    [701] = "number",
    [1700] = "number"
  }
  NULL = "\0"
  do
    local _obj_0 = require("bit")
    rshift, lshift, band = _obj_0.rshift, _obj_0.lshift, _obj_0.band
  end
  Postgres = _class_0
end
return {
  Postgres = Postgres
}
