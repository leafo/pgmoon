local flatten
do
  local __flatten
  __flatten = function(t, buffer)
    local _exp_0 = type(t)
    if "string" == _exp_0 then
      buffer[#buffer + 1] = t
    elseif "number" == _exp_0 then
      buffer[#buffer + 1] = tostring(t)
    elseif "table" == _exp_0 then
      for _index_0 = 1, #t do
        local thing = t[_index_0]
        __flatten(thing, buffer)
      end
    end
  end
  flatten = function(t)
    local buffer = { }
    __flatten(t, buffer)
    return table.concat(buffer)
  end
end
return {
  flatten = flatten
}
