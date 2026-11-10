#!/usr/bin/env bash
# C01 - Con el juego abierto: comprueba que la jaula no tiene salida.
# Uso: bash tools/c01/35-check-isolation.sh
set -uo pipefail

NS=metin2lab
SERVER_IP=10.10.10.10

ip netns list | awk '{print $1}' | grep -qx "$NS" \
  || { echo "ERROR: la jaula $NS no existe"; exit 1; }

echo "== rutas (no debe haber 'default') =="
sudo ip netns exec "$NS" ip route
if sudo ip netns exec "$NS" ip route | grep -q '^default'; then
  echo "PELIGRO: hay ruta por defecto"
  exit 2
fi

echo
echo "== direcciones =="
sudo ip netns exec "$NS" ip -brief addr

echo
echo "== conexiones del cliente (solo deberia aparecer $SERVER_IP) =="
sudo ip netns exec "$NS" ss -tanp 2>/dev/null || echo "ss no disponible"

echo
echo "== procesos dentro de la jaula (deberia estar wine/metin2client) =="
sudo ip netns pids "$NS" | while read -r pid; do
  [ -n "$pid" ] && ps -o pid=,comm=,args= -p "$pid" 2>/dev/null
done
if [ -z "$(sudo ip netns pids "$NS")" ]; then
  echo "PELIGRO: no hay ningun proceso dentro de la jaula"
fi

echo
echo "== intento a Internet (debe fallar) =="
if sudo ip netns exec "$NS" curl -m 5 -sS https://1.1.1.1 -o /dev/null 2>/dev/null; then
  echo "PELIGRO: hay salida a Internet"
else
  echo "OK: sin salida a Internet"
fi

echo
echo "== DNS (debe fallar) =="
echo "-- resolv.conf en la jaula:"
sudo ip netns exec "$NS" sh -c \
  'if [ -s /etc/resolv.conf ]; then cat /etc/resolv.conf; else echo "(vacio)"; fi'
echo "-- hosts en nsswitch:"
sudo ip netns exec "$NS" sh -c \
  "grep -E '^[[:space:]]*hosts:' /etc/nsswitch.conf || echo '(sin nsswitch)'"
if sudo ip netns exec "$NS" getent hosts example.com >/dev/null 2>&1; then
  echo "PELIGRO: resuelve nombres"
else
  echo "OK: sin DNS"
fi
