#!/usr/bin/env bash
# C01 - Crea la jaula de red: un namespace con una sola ruta al servidor.
# Uso: bash tools/c01/20-netns-up.sh
set -euo pipefail

NS=metin2lab
BR=virbr-lab
CLIENT_IP=10.10.10.20
SERVER_IP=10.10.10.10
VETH_HOST=veth-lab
VETH_NS=veth-m2

if ! ip link show "$BR" >/dev/null 2>&1; then
  echo "ERROR: no existe el puente $BR."
  echo "Arranca la VM FreeBSD (que crea virbr-lab) y vuelve a intentarlo."
  exit 1
fi

if ip netns list | awk '{print $1}' | grep -qx "$NS"; then
  echo "La jaula $NS ya existe; no la recreo."
else
  echo "== creando jaula $NS =="
  sudo ip netns add "$NS"

  echo "== creando par veth y colgandolo del puente =="
  sudo ip link add "$VETH_NS" type veth peer name "$VETH_HOST"
  sudo ip link set "$VETH_HOST" master "$BR"
  sudo ip link set "$VETH_HOST" up
  sudo ip link set "$VETH_NS" netns "$NS"

  echo "== IPv6 fuera =="
  sudo ip netns exec "$NS" sh -c \
    'echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6; echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6' \
    2>/dev/null || true

  echo "== loopback y veth =="
  sudo ip netns exec "$NS" ip link set lo up
  sudo ip netns exec "$NS" ip link set "$VETH_NS" up

  echo "== IP /32 y ruta unica al servidor =="
  sudo ip netns exec "$NS" ip addr add "$CLIENT_IP/32" dev "$VETH_NS"
  sudo ip netns exec "$NS" ip route add "$SERVER_IP/32" dev "$VETH_NS"
fi

echo "== resolv.conf vacio para la jaula =="
sudo mkdir -p "/etc/netns/$NS"
sudo sh -c ": > /etc/netns/$NS/resolv.conf"

echo "== nsswitch.conf para la jaula: hosts solo por files =="
# Un resolv.conf vacio NO impide que glibc pregunte a nss-resolve por D-Bus al
# systemd-resolved del host (que si tiene DNS). Con hosts:files, no hay modulo
# que pueda resolver nombres fuera de /etc/hosts dentro de la jaula.
if [ -f /etc/nsswitch.conf ] && grep -qE '^[[:space:]]*hosts:' /etc/nsswitch.conf; then
  sed -E 's/^[[:space:]]*hosts:.*/hosts:      files/' /etc/nsswitch.conf \
    | sudo tee "/etc/netns/$NS/nsswitch.conf" >/dev/null
else
  printf 'hosts:      files\n' | sudo tee "/etc/netns/$NS/nsswitch.conf" >/dev/null
fi

echo
echo "== rutas dentro de la jaula (NO debe haber 'default') =="
sudo ip netns exec "$NS" ip route
if sudo ip netns exec "$NS" ip route | grep -q '^default'; then
  echo "PELIGRO: hay una ruta por defecto en la jaula. NO sigas."
  exit 2
fi

echo
echo "== direcciones =="
sudo ip netns exec "$NS" ip -brief addr

echo
echo "== prueba al servidor (debe responder) =="
if sudo ip netns exec "$NS" ping -c 2 -W 2 "$SERVER_IP"; then
  echo "OK: el servidor responde"
else
  echo "AVISO: no responde el ping. Puede ser normal si FreeBSD bloquea ICMP;"
  echo "lo importante es TCP. Se comprueba al lanzar el cliente."
fi

echo
echo "== prueba a Internet (DEBE fallar) =="
if sudo ip netns exec "$NS" curl -m 5 -sS https://1.1.1.1 -o /dev/null 2>/dev/null; then
  echo "PELIGRO: la jaula tiene salida a Internet. NO sigas."
  exit 2
else
  echo "OK: sin salida a Internet"
fi

echo
echo "== DNS dentro de la jaula (DEBE fallar) =="
echo "-- hosts en nsswitch:"
sudo ip netns exec "$NS" sh -c "grep -E '^[[:space:]]*hosts:' /etc/nsswitch.conf || echo '(sin nsswitch)'"
if sudo ip netns exec "$NS" getent hosts example.com >/dev/null 2>&1; then
  echo "PELIGRO: resuelve nombres. NO sigas."
  exit 2
else
  echo "OK: sin DNS"
fi

echo
echo "OK. Siguiente: bash tools/c01/30-run-client.sh"
