-- OAuth SASL authentication support for PostgreSQL
-- Implements OAUTHBEARER mechanism as per RFC 7628

class OAuth
  -- Create OAUTHBEARER client-first message
  -- Format: gs2-header authzid kvpairs
  -- gs2-header = "n,,"
  -- authzid = ""
  -- kvpairs = "auth=Bearer " token [\x01 key "=" value]* \x01
  @create_client_first: (token, extra_params) =>
    params = extra_params or {}
    gs2_header = "n,,"
    auth_param = "\1auth=Bearer " .. token
    
    extra = ""
    for key, value in pairs params
      extra = extra .. "\1" .. key .. "=" .. value
    
    -- Final format: gs2-header + auth param + extra params + final \x01
    gs2_header .. auth_param .. extra .. "\1\1"

  -- Validate OAuth token format (basic check)
  @validate_token: (token) =>
    unless token and type(token) == "string" and #token > 0
      return false, "Invalid OAuth token: token must be a non-empty string"
    
    true

OAuth
