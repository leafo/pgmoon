# OAUTHBEARER Support Implementation for pgmoon

## Overview
Added complete OAUTHBEARER SASL authentication support to pgmoon, enabling PostgreSQL authentication using OAuth 2.0 bearer tokens as specified in RFC 7628.

## Files Modified/Created

### 1. `pgmoon/oauth.moon` (NEW)
Created a new MoonScript module implementing the OAuth SASL authentication logic:
- `OAuth.create_client_first(token, extra_params)` - Generates the OAUTHBEARER client-first message
- `OAuth.validate_token(token)` - Validates OAuth token format

The message format follows RFC 7628:
```
gs2-header + authzid + kvpairs
where:
  gs2-header = "n,,"  (no channel binding, no authzid)
  kvpairs = "\x01auth=Bearer <token>\x01\x01"
```

### 2. `pgmoon/init.moon` (MODIFIED)
Enhanced the PostgreSQL client with OAUTHBEARER support:

#### Changes to `scram_sha_256_auth` method:
- Added detection for OAUTHBEARER mechanism in SASL authentication
- Routes OAUTHBEARER requests to the new `oauthbearer_auth` method

#### New `oauthbearer_auth` method:
- Validates presence of `oauth_token` in configuration
- Creates and sends OAUTHBEARER client-first message
- Handles SASL authentication flow:
  - Sends initial SASL response with mechanism name and client-first message
  - Handles AuthenticationSASLContinue (auth_status 11) if server sends challenge
  - Sends empty response to complete the exchange
  - Performs final authentication check

### 3. `pgmoon/oauth.lua` (GENERATED)
Compiled Lua output from `oauth.moon`

### 4. `pgmoon/init.lua` (UPDATED)
Compiled Lua output from `init.moon` with OAUTHBEARER support

### 5. `examples/oauthbearer_example.lua` (NEW)
Created comprehensive example file demonstrating:
- Basic OAUTHBEARER authentication
- Connection pooling usage
- Error handling
- Usage in both OpenResty and standard Lua contexts

## Usage

To use OAUTHBEARER authentication, provide an `oauth_token` when creating a connection:

```lua
local pgmoon = require("pgmoon")
local pg = pgmoon.new({
  host = "127.0.0.1",
  port = "5432",
  database = "mydb",
  user = "postgres",
  oauth_token = "your-oauth-bearer-token"
})

assert(pg:connect())
```

## Authentication Flow

1. Client initiates connection with PostgreSQL
2. Server responds with SASL authentication request (auth_type 10)
3. Server includes "OAUTHBEARER" in list of supported mechanisms
4. Client detects OAUTHBEARER and routes to `oauthbearer_auth`
5. Client validates the OAuth token
6. Client generates client-first message with bearer token
7. Client sends SASL initial response
8. Server may send challenge (AuthenticationSASLContinue)
9. Client sends empty response if challenged
10. Server sends final authentication status
11. Client verifies authentication succeeded

## Technical Details

### SASL Message Types
- **AuthenticationSASL (10)**: Initial request with mechanism list
- **AuthenticationSASLContinue (11)**: Challenge from server
- **AuthenticationOk (0)**: Authentication succeeded

### Error Handling
- Missing `oauth_token`: Returns error "missing oauth_token, required for OAUTHBEARER auth"
- Invalid token format: Returns error "Invalid OAuth token: token must be a non-empty string"
- Authentication failures: Propagated through standard pgmoon error handling

## Requirements

- PostgreSQL server with OAUTHBEARER support (requires extension or custom authentication plugin)
- Valid OAuth 2.0 bearer token
- pgmoon 2.3.2.0 or later

## Testing

The implementation was verified to:
1. Successfully compile MoonScript to Lua
2. Load the OAuth module without errors
3. Validate tokens correctly
4. Generate properly formatted client-first messages

## Compatibility

This implementation is compatible with:
- Standard Lua
- LuaJIT
- OpenResty/nginx
- All existing pgmoon socket types (luasocket, nginx, cqueues)

## References

- RFC 7628: A Set of Simple Authentication and Security Layer (SASL) Mechanisms for OAuth
- PostgreSQL SASL Authentication: https://www.postgresql.org/docs/current/sasl-authentication.html
