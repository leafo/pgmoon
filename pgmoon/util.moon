
-- flattens arguments following the logic of ngx.socket's send method so that other sockets can emulate it
flatten = do
  __flatten = (t, buffer) ->
    switch type(t)
      when "string"
        buffer[#buffer + 1] = t
      when "number"
        buffer[#buffer + 1] = tostring t
      when "table"
        for thing in *t
          __flatten thing, buffer

  (t) ->
    buffer = {}
    __flatten t, buffer
    table.concat buffer

local encode_base64, decode_base64

if ngx
  {:encode_base64, :decode_base64} = ngx
else
  { :b64, :unb64 } = require "mime" -- provided by luasocket
  encode_base64 = (...) -> (b64 ...)
  decode_base64 = (...) -> (unb64 ...)

{:flatten, :encode_base64, :decode_base64}
