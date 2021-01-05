#!/bin/bash

pgroot=$(pwd)/pgdata
port=9999

function makecerts {
  # https://www.postgresql.org/docs/9.5/static/ssl-tcp.html
  (
    cd $pgroot

    openssl req -new -passout pass:itchzone -text -out server.req -subj "/C=US/ST=Leafo/L=Leafo/O=Leafo/CN=itch.zone"
    openssl rsa -passin pass:itchzone -in privkey.pem -out server.key
    rm privkey.pem
    openssl req -x509 -in server.req -text -key server.key -out server.crt
    chmod og-rwx server.key
  )
}

function start {
	docker run --rm --name pgmoon-test -p 127.0.0.1:9999:5432/tcp -e POSTGRES_PASSWORD=pgmoon -d postgres > /dev/null
	until (PGHOST=127.0.0.1 PGPORT=9999 PGUSER=postgres PGPASSWORD=pgmoon psql -c '' 2> /dev/null); do :; done
}

function stop {
	docker stop pgmoon-test 2> /dev/null
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
