.PHONY: build test local show_types lint

build:
	moonc pgmoon

test: build
	busted -v

local:
	tup upd
	luarocks make --local pgmoon-dev-1.rockspec

show_types:
	psql -U postgres -c "select oid, typname, typcategory, typelem from pg_type where typcategory in ('A', 'B', 'N', 'D', 'S');"

lint:
	moonc -l pgmoon
