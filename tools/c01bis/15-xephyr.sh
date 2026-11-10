#!/usr/bin/env bash
# C01-bis - Arranca Xephyr: un servidor X anidado que solo muestra las ventanas
# del cliente. El usuario metin2 no ve el escritorio real, solo este display.
# Uso: bash tools/c01bis/15-xephyr.sh
set -euo pipefail

DISP=:7
GEOM="${GEOM:-1280x800}"
SOCK="/tmp/.X11-unix/X${DISP#:}"
LOGFILE="/tmp/xephyr-c01bis.log"

display_ok() {
  [ -S "$SOCK" ] || return 1
  if command -v xdpyinfo >/dev/null 2>&1; then
    xdpyinfo -display "$DISP" >/dev/null 2>&1
  elif command -v xset >/dev/null 2>&1; then
    DISPLAY="$DISP" xset q >/dev/null 2>&1
  else
    return 0
  fi
}

command -v Xephyr >/dev/null 2>&1 || {
  echo "ERROR: falta Xephyr."
  echo "Instalalo con: sudo pacman -S xorg-server-xephyr"
  exit 1
}

if display_ok; then
  echo "Xephyr ya esta en $DISP"
  exit 0
fi

echo "== arrancando Xephyr en $DISP ($GEOM) =="
# -ac desactiva el control de acceso SOLO del display :7. El escritorio real
# sigue siendo :0 y no se abre. Asi metin2 puede pintar sin cookie y sin ver
# nada del usuario real.
nohup Xephyr "$DISP" -screen "$GEOM" -ac -noreset \
  -title "Metin2 (jaula C01-bis)" >"$LOGFILE" 2>&1 &

for _ in 1 2 3 4 5; do
  sleep 1
  if display_ok; then
    echo "OK: Xephyr listo en $DISP"
    echo "Para sacar el raton de la ventana: Ctrl+Shift"
    exit 0
  fi
done

echo "ERROR: Xephyr no respondio. Mira $LOGFILE"
exit 1
