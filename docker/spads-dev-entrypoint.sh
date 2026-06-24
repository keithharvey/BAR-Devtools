#!/bin/bash
# Dev entrypoint for the from-scratch SPADS image (docker/spads.dev.Dockerfile).
# The installer set SPADS up as a LAN autohost against springrts; override the
# lobby config for the dockerized teiserver, drop in the BAR plugins, provision
# the game, then launch.
set -e

_term() { kill -TERM "$child" 2>/dev/null; wait "$child"; }
trap _term SIGTERM SIGINT

cd /opt/spads
conf=etc/spads.conf

# teiserver advertises STLS as an accepted command even with no cert, so lobbyTls:auto
# tries (and fails) TLS. Plain is fine on localhost dev -> force lobbyTls:off.
sed -i \
  -e "s|^lobbyHost:.*|lobbyHost:${SPADS_LOBBY_HOST:-127.0.0.1}|" \
  -e "s|^lobbyLogin:.*|lobbyLogin:${SPADS_LOBBY_LOGIN:-spadsbot}|" \
  -e "s|^lobbyPassword:.*|lobbyPassword:${SPADS_LOBBY_PASSWORD:-password}|" \
  -e "s|^lobbyTls:.*|lobbyTls:${SPADS_LOBBY_TLS:-off}|" \
  -e "s|^autoLoadPlugins:.*|autoLoadPlugins:${SPADS_PLUGINS:-BarChobby;ModeCommand}|" \
  "$conf"

# teiserver's lobby-name rule forbids parentheses; the default preset names have them.
sed -i 's|^battleName:.*|battleName:BAR Dev autohost|' etc/hostingPresets.conf 2>/dev/null || true

# Host on the dev's local RecoilEngine build (matches bar::launch --engine local-build)
# instead of the installer's auto-managed engine, for engine-matched end-to-end testing.
if [ "${SPADS_LOCAL_ENGINE:-}" = "1" ] && [ -x /local-engine/spring-dedicated ]; then
  echo "Using mounted local RecoilEngine build for hosting."
  sed -i \
    -e "s|^autoManagedSpringVersion:.*|autoManagedSpringVersion:|" \
    -e "s|^unitsyncDir:.*|unitsyncDir:/local-engine|" \
    -e "s|^springServer:.*|springServer:/local-engine/spring-dedicated|" \
    "$conf"
fi

# BAR autohost plugins (ModeCommand) from the mounted BYAR-Chobby checkout.
if [ -d /spads_plugins ]; then
  # pluginsDir:plugins resolves relative to varDir (-> var/plugins).
  mkdir -p var/plugins
  for d in /spads_plugins/*/; do
    cp "$d"*.py "$d"*.pm "$d"*.dat var/plugins/ 2>/dev/null || true
    cp "$d"*.conf etc/ 2>/dev/null || true
  done
fi

# The engine is auto-managed; the rapid game is not -- provision byar:test once.
prd="$(find var/spring/recoil -name pr-downloader -type f 2>/dev/null | head -1)"
data="$(pwd)/var/spring/data"
if [ -n "$prd" ] && [ ! -f "$data/.byar-provisioned" ]; then
  echo "Downloading byar:test from the BAR CDN (first run only)..."
  if "$prd" --filesystem-writepath "$data" --download-game byar:test; then
    touch "$data/.byar-provisioned"
  else
    echo "WARNING: game download failed. SPADS may not open a battle."
  fi
fi

perl spads.pl "$conf" &
child=$!
wait "$child"
