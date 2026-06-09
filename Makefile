.PHONY: build test test_resty local show_types lint bench bench_luasocket

build:
	moonc pgmoon

bench: build
	moonc benchmark.moon
	resty benchmark.lua

bench_luasocket: build
	moonc benchmark.moon
	luajit benchmark.lua

test: build
	busted spec/pgmoon_spec.moon spec/pgmoon_pool_spec.moon spec/pgmoon_unix_spec.moon
	sleep 1
	busted spec/pgmoon_ssl_spec.moon

test_resty: build
	resty spec/resty_busted.lua spec/pgmoon_spec.moon spec/pgmoon_pool_spec.moon spec/pgmoon_unix_spec.moon
	sleep 1
	resty spec/resty_busted.lua spec/pgmoon_ssl_spec.moon

local: build
	luarocks --lua-version=5.1 make --local pgmoon-dev-1.rockspec

show_types:
	psql -U postgres -c "select oid, typname, typcategory, typelem from pg_type where typcategory in ('A', 'B', 'N', 'D', 'S');"

lint:
	moonc -l pgmoon
