#!/bin/bash
set -e

DB_HOST="${TEI_DB_HOSTNAME:-postgres}"
DB_PORT="${TEI_DB_PORT:-5432}"

echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}..."
until bash -c "echo > /dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; do
  sleep 1
done
echo "PostgreSQL is ready."

INIT_MARKER="/app/.devtools/.initialized"
mkdir -p /app/.devtools

if [ ! -f "$INIT_MARKER" ]; then
  echo ""
  echo "========================================="
  echo "  First run: initializing database"
  echo "========================================="
  echo ""

  mix ecto.create 2>/dev/null || true

  echo "--- Seeding fake data (this drops and recreates the DB) ---"
  mix teiserver.fakedata

  sleep 2

  echo "--- Setting up Tachyon OAuth ---"
  mix teiserver.tachyon_setup

  sleep 1

  echo "--- Creating SPADS bot account ---"
  mix run /setup-spads-bot.exs

  touch "$INIT_MARKER"

  echo ""
  echo "========================================="
  echo "  Initialization complete!"
  echo "  Login: root@localhost / password"
  echo "========================================="
  echo ""
else
  echo "--- Running pending migrations ---"
  mix ecto.migrate
fi

# Self-signed cert for the spring lobby's STLS/TLS (TEI_TLS_* point here). Without
# it use_tls? is false, SPADS' STARTTLS on 8200 fails, and it can't connect.
if [ -n "${TEI_TLS_PRIVATE_KEY_PATH:-}" ]; then
  mkdir -p "$(dirname "$TEI_TLS_PRIVATE_KEY_PATH")"
  if [ ! -f "$TEI_TLS_PRIVATE_KEY_PATH" ]; then
    echo "--- Generating self-signed lobby TLS cert ---"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=localhost" \
      -keyout "$TEI_TLS_PRIVATE_KEY_PATH" -out "$TEI_TLS_CERT_PATH"
  fi
  # use_tls? also turns on the web HTTPS endpoint, whose DHE ciphers need a dhparam file.
  if [ -n "${TEI_TLS_DH_FILE_PATH:-}" ] && [ ! -f "$TEI_TLS_DH_FILE_PATH" ]; then
    echo "--- Generating DH params (one-time, slow) ---"
    openssl dhparam -out "$TEI_TLS_DH_FILE_PATH" 2048
  fi
fi

echo "=== Starting Teiserver ==="
exec mix phx.server
