FROM ghcr.io/leafo/lapis-archlinux-itchio
MAINTAINER leaf corcoran <leafot@gmail.com>

WORKDIR /pgmoon

ADD . .

ARG LUA=lua5.1

ENTRYPOINT ./ci.sh