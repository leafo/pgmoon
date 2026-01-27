local OAuth
do
  local _class_0
  local _base_0 = { }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "OAuth"
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
  self.create_client_first = function(self, token, extra_params)
    local params = extra_params or { }
    local gs2_header = "n,,"
    local auth_param = "\1auth=Bearer " .. token
    local extra = ""
    for key, value in pairs(params) do
      extra = extra .. "\1" .. key .. "=" .. value
    end
    return gs2_header .. auth_param .. extra .. "\1\1"
  end
  self.validate_token = function(self, token)
    if not (token and type(token) == "string" and #token > 0) then
      return false, "Invalid OAuth token: token must be a non-empty string"
    end
    return true
  end
  OAuth = _class_0
end
return OAuth
