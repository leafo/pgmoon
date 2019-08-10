.PHONY: build

build: lint
	moonc pgmoon

test: build
	busted -v

local: build
	luarocks --lua-version=5.1 make --local pgmoon-dev-1.rockspec

show_types:
	psql -U postgres -c "select oid, typname, typcategory, typelem from pg_type where typcategory in ('A', 'B', 'N', 'D', 'S');"

lint:
	moonc -l pgmoon

all: lint build test local show_types

deb: build
	DEB_BUILD_OPTIONS=nocheck debuild --no-tgz-check -i -us -uc -b
