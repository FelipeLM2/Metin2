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
sudo ip netns exec "$NS" ss -tnp 2>/dev/null || echo "ss no disponible"

echo
echo "== intento a Internet (debe fallar) =="
if sudo ip netns exec "$NS" curl -m 5 -sS https://1.1.1.1 -o /dev/null 2>/dev/null; then
  echo "PELIGRO: hay salida a Internet"
else
  echo "OK: sin salida a Internet"
fi

echo
echo "== DNS (debe fallar) =="
if sudo ip netns exec "$NS" getent hosts example.com >/dev/null 2>&1; then
  echo "PELIGRO: resuelve nombres"
else
  echo "OK: sin DNS"
fi
