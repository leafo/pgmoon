-- Example: Using OAUTHBEARER authentication with pgmoon
-- 
-- OAUTHBEARER is a SASL mechanism for OAuth 2.0 bearer token authentication
-- as defined in RFC 7628. It allows PostgreSQL to authenticate users using
-- OAuth 2.0 access tokens instead of passwords.
--
-- Prerequisites:
-- 1. PostgreSQL server must be configured to support OAUTHBEARER authentication
-- 2. You need a valid OAuth 2.0 bearer token
--
-- Note: This example assumes you have a PostgreSQL server configured with
-- OAUTHBEARER support. Standard PostgreSQL installations do not include
-- OAUTHBEARER by default and require extensions or custom authentication plugins.

local pgmoon = require("pgmoon")

-- Example 1: Basic OAUTHBEARER authentication
local function example_basic_oauth()
  print("Example 1: Basic OAUTHBEARER authentication")
  
  -- Create a new connection with OAuth token
  local pg = pgmoon.new({
    host = "127.0.0.1",
    port = "5432",
    database = "mydb",
    user = "postgres",
    oauth_token = "your-oauth-bearer-token-here"
  })

  -- Connect to the database
  local success, err = pg:connect()
  
  if not success then
    print("Failed to connect:", err)
    return
  end
  
  print("Successfully connected using OAUTHBEARER!")
  
  -- Execute a simple query
  local result, err = pg:query("SELECT current_user, version()")
  
  if not result then
    print("Query failed:", err)
  else
    print("Current user:", result[1].current_user)
    print("PostgreSQL version:", result[1].version)
  end
  
  -- Clean up
  pg:disconnect()
end

-- Example 2: Using OAUTHBEARER with connection pooling
local function example_with_pooling()
  print("\nExample 2: OAUTHBEARER with keepalive")
  
  local pg = pgmoon.new({
    host = "127.0.0.1",
    port = "5432",
    database = "mydb",
    user = "postgres",
    oauth_token = "your-oauth-bearer-token-here"
  })

  local success, err = pg:connect()
  
  if not success then
    print("Failed to connect:", err)
    return
  end
  
  print("Connected successfully!")
  
  -- Execute query
  local result = pg:query("SELECT 1 as value")
  
  if result then
    print("Query result:", result[1].value)
  end
  
  -- Keep connection alive for reuse (if using OpenResty/nginx)
  -- pg:keepalive()
  
  pg:disconnect()
end

-- Example 3: Error handling
local function example_error_handling()
  print("\nExample 3: Error handling with invalid token")
  
  local pg = pgmoon.new({
    host = "127.0.0.1",
    port = "5432",
    database = "mydb",
    user = "postgres",
    oauth_token = ""  -- Invalid empty token
  })

  local success, err = pg:connect()
  
  if not success then
    print("Expected error:", err)
    -- Should print: "Invalid OAuth token: token must be a non-empty string"
  end
end

-- Main execution
if ngx then
  -- Running in OpenResty/nginx context
  print("Running in OpenResty context")
  example_basic_oauth()
else
  -- Running in standard Lua
  print("Running in standard Lua context")
  print("Note: These examples require a PostgreSQL server with OAUTHBEARER support")
  print("")
  
  -- Uncomment to run examples (requires proper PostgreSQL setup):
  -- example_basic_oauth()
  -- example_with_pooling()
  example_error_handling()
end
