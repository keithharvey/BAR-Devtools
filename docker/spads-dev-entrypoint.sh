#!/bin/bash
set -e

_term() {
  echo "Caught termination signal"
  kill -TERM "$child" 2>/dev/null
  wait "$child"
}
trap _term SIGTERM SIGINT

cp -R /spads_etc/* /opt/spads/etc/ 2>/dev/null || true
cp -R /spads_var/* /opt/spads/var/ 2>/dev/null || true

# Use the dev config instead of production config
cp /spads_dev.conf /opt/spads/etc/spads_dev.conf

mkdir -p /opt/spads/var/log
mkdir -p /opt/spads/var/plugins
mkdir -p /opt/spads/var/spring
mkdir -p /opt/spads/var/spads_dev/log

# lobby-repo plugin dirs: *.conf -> etc, code/help -> var/plugins
for d in /spads_plugins/*/; do
  cp "$d"*.conf /opt/spads/etc/ 2>/dev/null || true
  cp "$d"*.py "$d"*.pm "$d"*.dat /opt/spads/var/plugins/ 2>/dev/null || true
done

pidfiles=$(find /opt/spads/var -name "*.pid" -type f 2>/dev/null)
if [ -n "$pidfiles" ]; then
  echo "Cleaning stale pid files"
  echo "$pidfiles" | xargs rm -f
fi

# byar:test is rapid content (packages/pool, not games/), so gate on a marker.
# The bundled pr-downloader (0.7-611) can't reach the BAR CDN; use the current
# engine overlaid by docker/spads.Dockerfile, which honors PRD_RAPID_REPO_MASTER.
prd="$(find /opt/bar-engine -name pr-downloader -type f 2>/dev/null | head -1)"
[ -n "$prd" ] || prd="/spring-engines/latest/pr-downloader"
if [ ! -f "${SPRING_DATADIR}/.byar-provisioned" ]; then
  echo "Downloading BAR game (byar:test) + default map (first run only)..."
  # Map must match spads_dev.conf's `map:` or SPADS can't open its battle.
  if "$prd" --filesystem-writepath "${SPRING_DATADIR}" --download-game byar:test \
     && "$prd" --filesystem-writepath "${SPRING_DATADIR}" --download-map "Comet Catcher Remake 1.8"; then
    touch "${SPRING_DATADIR}/.byar-provisioned"
  else
    echo "WARNING: Game/map download failed. SPADS may not start properly."
  fi
fi

echo "Starting SPADS with dev config, connecting to ${SPADS_LOBBY_HOST:-127.0.0.1}:8200..."

perl /opt/spads/spads.pl /opt/spads/etc/spads_dev.conf \
  ${SPADS_ARGS} &

child=$!
echo "SPADS PID: $child"
wait "$child"
