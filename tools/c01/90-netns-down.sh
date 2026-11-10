#!/usr/bin/env bash
# C01 - Borra las jaulas de red: la del juego (metin2lab) y la de Xephyr
# (m2xephyr). Antes cierra Xephyr :7 y el wineserver del cliente, para no
# dejar la ventana ni procesos colgando. El prefijo y el cliente no se tocan.
# Uso: bash tools/c01/90-netns-down.sh
set -uo pipefail

NS=metin2lab
XNS=m2xephyr
U=metin2
PREFIX="/home/$U/metin2lab/wine/prefix"

echo "== cerrando Xephyr :7 =="
xephyr_pids() {
  pgrep -x Xephyr -a 2>/dev/null \
    | awk 'index($0, "Xephyr :7") {print $1}' \
    || true
}

PIDS="$(xephyr_pids)"
if [ -n "$PIDS" ]; then
  # shellcheck disable=SC2086
  sudo kill $PIDS 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    [ -z "$(xephyr_pids)" ] && break
    sleep 1
  done
  if [ -n "$(xephyr_pids)" ]; then
    echo "AVISO: Xephyr sigue vivo; revisa: pgrep -x Xephyr -a"
  else
    echo "Xephyr cerrado"
  fi
else
  echo "Xephyr no estaba corriendo"
fi
# Si el socket quedo huerfano, Xephyr no arrancaria la proxima vez.
if [ -z "$(xephyr_pids)" ]; then
  sudo rm -f /tmp/.X7-lock /tmp/.X11-unix/X7 2>/dev/null || true
fi

echo
echo "== cerrando el wineserver del cliente =="
if id "$U" >/dev/null 2>&1 && [ -d "$PREFIX" ]; then
  sudo -u "$U" env HOME="/home/$U" WINEPREFIX="$PREFIX" WINEARCH=win64 \
    wineserver -k 2>/dev/null || true
  echo "wineserver de $U cerrado (si estaba)"
else
  echo "(el usuario $U o el prefijo no existen todavia; nada que cerrar)"
fi

echo
for n in "$NS" "$XNS"; do
  if ip netns list | awk '{print $1}' | grep -qx "$n"; then
    sudo ip netns del "$n"
    echo "jaula $n borrada"
  else
    echo "la jaula $n no existia"
  fi
  sudo rm -rf "/etc/netns/$n"
  echo "limpio /etc/netns/$n"
done
