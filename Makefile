
.PHONY: test local

test:
	busted

local:
	tup upd
	luarocks make --local pgmoon-dev-1.rockspec
