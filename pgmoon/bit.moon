has_bit53, bit53 = pcall require, "pgmoon.bit53"
if has_bit53
	return bit53

has_bit, bit = pcall require, "bit"
if has_bit
	return bit

has_bit32, bit32 = pcall require, "bit32"
if has_bit32
	return bit32

error "Please install lua-bitop: $ luarocks install luabitop"
