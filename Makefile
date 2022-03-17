.PHONY: build test test_resty local show_types lint

build:
	moonc pgmoon

test: build
	busted -v

test_resty: build
	resty spec/resty_busted.lua spec/pgmoon_spec.moon

local: build
	luarocks --lua-version=5.1 make --local pgmoon-dev-1.rockspec

show_types:
	psql -U postgres -c "select oid, typname, typcategory, typelem from pg_type where typcategory in ('A', 'B', 'N', 'D', 'S');"

lint:
	moonc -l pgmoon
