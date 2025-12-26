
HOST = "127.0.0.1"
PORT = "9999"
USER = "postgres"
PASSWORD = "pgmoon"
DB = "pgmoon_test"

SOCKET_DIR = "/tmp/pgmoon-test-socket"
SOCKET_PATH = "#{SOCKET_DIR}/.s.PGSQL.5432"

shell_escape = (str) -> str\gsub "'", "'\\''"

psql = (query) ->
  os.execute "PGHOST='#{shell_escape HOST}' PGPORT='#{shell_escape PORT}' PGUSER='#{shell_escape USER}' PGPASSWORD='#{shell_escape PASSWORD}' psql -c '#{query}'"

-- psql via unix socket using local psql with socket path
psql_unix = (query) ->
  os.execute "PGHOST='#{shell_escape SOCKET_DIR}' PGUSER='#{shell_escape USER}' PGPASSWORD='#{shell_escape PASSWORD}' psql -c '#{shell_escape query}'"


{:psql, :psql_unix, :HOST, :PORT, :USER, :PASSWORD, :DB, :SOCKET_PATH, :SOCKET_DIR}
