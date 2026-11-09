#!/usr/bin/env bash
# C01 - Lanza el cliente dentro de la jaula, como tu usuario (nunca como root).
# Uso: bash tools/c01/30-run-client.sh
set -euo pipefail

NS=metin2lab
BASE="$HOME/metin2lab/wine"
PREFIX="$BASE/prefix"
GAME="$PREFIX/drive_c/Games/Metin2"
LOGDIR="$BASE/logs"
LOG="$LOGDIR/client-$(date +%Y%m%d-%H%M%S).log"

ip netns list | awk '{print $1}' | grep -qx "$NS" \
  || { echo "ERROR: la jaula $NS no existe. Ejecuta 20-netns-up.sh"; exit 1; }
[ -d "$GAME" ] || { echo "ERROR: no existe $GAME. Ejecuta 10-prefix.sh"; exit 1; }

EXE=""
for c in metin2client.exe Metin2Client.exe metin2.exe Metin2.exe; do
  if [ -f "$GAME/$c" ]; then EXE="$c"; break; fi
done
if [ -z "$EXE" ]; then
  echo "ERROR: no encuentro un ejecutable conocido en $GAME"
  echo "Candidatos:"
  find "$GAME" -maxdepth 1 -type f -iname '*.exe' -printf '  %f\n' | sort || true
  exit 1
fi

WINE_BIN=$(command -v wine)
mkdir -p "$LOGDIR"

echo "== lanzando $EXE dentro de $NS =="
echo "log: $LOG"
echo "Cuando aparezca la ventana, entra al juego. Deja esta terminal abierta."
echo

cd "$GAME"

set +e
sudo ip netns exec "$NS" \
  sudo -u "$USER" \
  env HOME="$HOME" \
      DISPLAY="${DISPLAY:-:0}" \
      XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
      WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
      XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
      DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
      WINEPREFIX="$PREFIX" \
      WINEARCH=win32 \
      WINEDEBUG=-all \
      WINEDLLOVERRIDES="mscoree,mshtml=;d3d9,dxgi=n,b" \
      DXVK_HUD="${DXVK_HUD:-fps,gpu,devinfo}" \
      "$WINE_BIN" "$EXE" 2>&1 | tee "$LOG"
launch_rc=${PIPESTATUS[0]}
set -e

echo
echo "== el cliente termino con codigo $launch_rc =="
echo "== cerrando wineserver del prefijo =="
WINEPREFIX="$PREFIX" WINEARCH=win32 wineserver -k 2>/dev/null || true
echo "log guardado en: $LOG"
