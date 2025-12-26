
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
-- Use explicit -h flag to override any PGHOST env var from CI
psql_unix = (query) ->
  result = os.execute "PGPASSWORD='#{shell_escape PASSWORD}' psql -h '#{shell_escape SOCKET_DIR}' -U '#{shell_escape USER}' -c '#{shell_escape query}'"
  if result != true and result != 0
    -- On failure, show debug info
    io.stderr\write "psql_unix failed, showing debug info:\n"
    os.execute "docker ps -a --filter name=pgmoon-test"
    os.execute "docker logs --tail 50 pgmoon-test 2>&1 || true"
    os.execute "ls -la '#{shell_escape SOCKET_DIR}' 2>&1 || true"
  result


{:psql, :psql_unix, :HOST, :PORT, :USER, :PASSWORD, :DB, :SOCKET_PATH, :SOCKET_DIR}
