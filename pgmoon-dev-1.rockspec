package = "pgmoon"
version = "dev-1"

source = {
  url = "git://github.com/leafo/pgmoon.git"
}

description = {
  summary = "Postgres driver for OpenResty and Lua",
  detailed = [[]],
  homepage = "https://github.com/leafo/pgmoon",
  maintainer = "Leaf Corcoran <leafot@gmail.com>",
  license = "MIT"
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["pgmoon.socket"] = "pgmoon/socket.lua",
    ["pgmoon"] = "pgmoon/init.lua",
  },
}

