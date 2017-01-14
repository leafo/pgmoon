.PHONY: build test local show_types lint

deb_revision = 1

build:
	moonc pgmoon

test: build
	busted -v

local: build
	luarocks make --local pgmoon-dev-1.rockspec

show_types:
	psql -U postgres -c "select oid, typname, typcategory, typelem from pg_type where typcategory in ('A', 'B', 'N', 'D', 'S');"

lint:
	moonc -l pgmoon

deb: build
	DEB_BUILD_OPTIONS=nocheck debuild -i -us -uc -b --no-tgz-check
