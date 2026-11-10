#!/usr/bin/env bash
# C01-bis - Restaura el cliente desde la copia dorada btrfs.
# No borra nada: aparta el laboratorio actual (metin2lab.roto-<fecha>) y crea
# uno nuevo desde metin2lab-golden. El progreso del juego sigue en MariaDB.
# Uso: bash tools/c01bis/85-reset.sh
set -euo pipefail

U=metin2
LAB="/home/$U/metin2lab"
GOLDEN="/home/$U/metin2lab-golden"
STAMP="$(date +%Y%m%d-%H%M%S)"
BROKEN="/home/$U/metin2lab.roto-$STAMP"
PREFIX="$LAB/wine/prefix"

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
  AS_U=(runuser -u "$U" --)
else
  SUDO=(sudo)
  AS_U=(sudo -u "$U")
fi

"${SUDO[@]}" btrfs subvolume show "$GOLDEN" >/dev/null 2>&1 || {
  echo "ERROR: no existe la copia dorada $GOLDEN."
  echo "Ejecuta primero: bash tools/c01bis/80-snapshot.sh"
  exit 1
}
"${SUDO[@]}" btrfs subvolume show "$LAB" >/dev/null 2>&1 || {
  echo "ERROR: $LAB no es un subvolumen; no hay nada que restaurar con este metodo."
  exit 1
}

echo "== cerrando el wineserver del cliente =="
"${AS_U[@]}" env HOME="/home/$U" WINEPREFIX="$PREFIX" WINEARCH=win64 \
  wineserver -k 2>/dev/null || true

echo "== apartando el laboratorio actual =="
if [ -e "$BROKEN" ] || "${SUDO[@]}" test -e "$BROKEN"; then
  echo "ERROR: ya existe $BROKEN. No lo sobreescribo."
  exit 1
fi
"${SUDO[@]}" mv "$LAB" "$BROKEN"
"${SUDO[@]}" btrfs subvolume snapshot "$GOLDEN" "$LAB"
"${SUDO[@]}" chown -R "$U:$U" "$LAB"

echo
echo "OK: $LAB restaurado desde $GOLDEN"
echo "El laboratorio anterior queda en $BROKEN (no se ha borrado)."
echo "Cuando compruebes que todo va, puedes borrarlo con:"
echo "  sudo btrfs subvolume delete $BROKEN"
