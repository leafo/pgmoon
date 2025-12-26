#!/bin/bash
set -eo pipefail

pgroot=$(pwd)/pgdata
port=9999

postgres_version=${DOCKER_POSTGRES_VERSION:-latest}

function makecerts {
  # https://www.postgresql.org/docs/9.5/static/ssl-tcp.html
  (
    cd $pgroot

    openssl req -new -passout pass:itchzone -text -out server.req -subj "/C=US/ST=Leafo/L=Leafo/O=Leafo/CN=itch.zone"
    openssl rsa -passin pass:itchzone -in privkey.pem -out server.key
    rm privkey.pem
    openssl req -x509 -sha1 -in server.req -text -key server.key -out server.crt
    chmod og-rwx server.key
  )
}

function start {
  INIT_SCRIPT=""

  if [ "$1" = "ssl" ]; then
    INIT_SCRIPT="-v $(pwd)/spec/docker_enable_ssl.sh:/docker-entrypoint-initdb.d/docker_enable_ssl.sh"
  fi

  echo "$(tput setaf 4)Starting postgresql $postgres_version (docker run) $1 $(tput sgr0)"
  docker run --rm --name pgmoon-test \
    -p 127.0.0.1:$port:5432/tcp \
    -e POSTGRES_PASSWORD=pgmoon \
    $INIT_SCRIPT \
    -d \
    postgres:$postgres_version > /dev/null


  # -v "$pgroot:/var/lib/postgresql/data" \ # this can be used to inspect logs since we'll have the server data dir available after the sever stops

  echo "$(tput setaf 4)Waiting for server to be ready$(tput sgr0)"
  until (PGHOST=127.0.0.1 PGPORT=$port PGUSER=postgres PGPASSWORD=pgmoon psql -c 'SELECT pg_reload_conf()' 2> /dev/null); do :; done
  echo "$(tput setaf 4)Sever is ready$(tput sgr0)"
}

function stop {
  docker stop pgmoon-test > /dev/null 2>&1
}

function start_legacy {
  [ -d "${pgroot}" ] && rm -rf $pgroot
  initdb --locale 'en_US.UTF-8' -E 'UTF8' -A 'trust' -D $pgroot

  if [ "$1" = "ssl" ]; then
    # install ssl
    makecerts

    echo "
ssl = on
ssl_cert_file = '${pgroot}/server.crt'
ssl_key_file = '${pgroot}/server.key'
# ssl_ca_file = ''
# ssl_crl_file = ''
    " >> $pgroot/postgresql.conf
  fi

  postgresql-check-db-dir $pgroot
  PGPORT=$port pg_ctl -s -o '-k /tmp' -D $pgroot start -w
  createuser -h localhost -p $port -w -s postgres
  createdb -h localhost -p $port -U postgres pgmoon_test
}

function stop_legacy {
  pg_ctl -s -D $pgroot stop -m fast
}

case "$1" in
  start)
    start "$2"
    ;;
  stop)
    stop
    ;;
  *)
    echo "usage: spec/postgres.sh {start|stop}"
esac
