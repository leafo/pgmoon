#!/bin/bash
set -e

# This script will configure postgres to accept SSL connections within the docker image
# Since it generates the key inside of the image, it requires the full postgres image and not an alpine linux variant

cd /var/lib/postgresql

ls -lah >&2

openssl req -new -passout pass:itchzone -text -out server.req -subj "/C=US/ST=Leafo/L=Leafo/O=Leafo/CN=itch.zone"
openssl rsa -passin pass:itchzone -in privkey.pem -out server.key
rm privkey.pem
openssl req -x509 -in server.req -text -key server.key -out server.crt
chmod og-rwx server.key

echo "
ssl = on
ssl_cert_file = '$(pwd)/server.crt'
ssl_key_file = '$(pwd)/server.key'
" >> data/postgresql.conf
