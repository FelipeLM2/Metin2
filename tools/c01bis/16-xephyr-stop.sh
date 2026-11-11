#!/usr/bin/env bash
# C01-bis - Cierra SOLO el Xephyr de :7 y limpia su lock/socket.
# No borra las jaulas ni el cliente: para eso esta tools/c01/90-netns-down.sh.
# Sirve como salida de emergencia si Xephyr se queda a pantalla completa.
# Uso: bash tools/c01bis/16-xephyr-stop.sh
set -uo pipefail

DISP=:7
SOCK="/tmp/.X11-unix/X${DISP#:}"
LOCK="/tmp/.X${DISP#:}-lock"

xephyr_pids() {
  pgrep -x Xephyr -a 2>/dev/null \
    | awk -v pat="Xephyr $DISP" 'index($0, pat) {print $1}' \
    || true
}

PIDS="$(xephyr_pids)"
if [ -z "$PIDS" ]; then
  echo "Xephyr $DISP no estaba corriendo."
else
  echo "== cerrando Xephyr $DISP ($PIDS) =="
  # shellcheck disable=SC2086
  kill $PIDS 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    [ -z "$(xephyr_pids)" ] && break
    sleep 1
  done
  REMAIN="$(xephyr_pids)"
  if [ -n "$REMAIN" ]; then
    echo "AVISO: no cerro con SIGTERM; envio SIGKILL a $REMAIN"
    # shellcheck disable=SC2086
    kill -KILL $REMAIN 2>/dev/null || true
    sleep 1
  fi
fi

if [ -z "$(xephyr_pids)" ]; then
  sudo rm -f "$LOCK" "$SOCK" 2>/dev/null || true
  echo "OK: Xephyr $DISP cerrado y lock/socket limpios."
  echo "Las jaulas y el cliente no se tocan; para todo: bash tools/c01/90-netns-down.sh"
else
  echo "ERROR: Xephyr $DISP sigue vivo. Revisa: pgrep -x Xephyr -a"
  exit 1
fi
