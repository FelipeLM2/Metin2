#!/usr/bin/env bash
# C01 - Borra la jaula de red. El cliente y el prefijo no se tocan.
# Uso: bash tools/c01/90-netns-down.sh
set -uo pipefail

NS=metin2lab

if ip netns list | awk '{print $1}' | grep -qx "$NS"; then
  sudo ip netns del "$NS"
  echo "jaula $NS borrada"
else
  echo "la jaula $NS no existia"
fi

sudo rm -rf "/etc/netns/$NS"
echo "limpio /etc/netns/$NS"
