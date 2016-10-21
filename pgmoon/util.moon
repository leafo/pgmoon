
-- make luasockets send behave like openresty's
flatten = do
  __flatten = (t, buffer) ->
    switch type(t)
      when "string"
        buffer[#buffer + 1] = t
      when "table"
        for thing in *t
          __flatten thing, buffer

  (t) ->
    buffer = {}
    __flatten t, buffer
    table.concat buffer

{:flatten}
