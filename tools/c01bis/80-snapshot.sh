#!/usr/bin/env bash
# C01-bis - Convierte /home/metin2/metin2lab en subvolumen btrfs y crea una
# copia dorada read-only (metin2lab-golden). El progreso del juego NO vive
# aqui: esta en MariaDB dentro de la FreeBSD. Esto guarda una instalacion
# conocida-buena del cliente (prefijo, DXVK, config) para volver a ella.
# Uso: bash tools/c01bis/80-snapshot.sh
set -euo pipefail

U=metin2
LAB="/home/$U/metin2lab"
GOLDEN="/home/$U/metin2lab-golden"
OLD="/home/$U/metin2lab.pre-subvol"
PREFIX="$LAB/wine/prefix"

if [ "$(id -u)" -eq 0 ]; then
  SUDO=()
  AS_U=(runuser -u "$U" --)
else
  SUDO=(sudo)
  AS_U=(sudo -u "$U")
fi

[ -d "$LAB" ] || "${SUDO[@]}" test -d "$LAB" || {
  echo "ERROR: no existe $LAB. Ejecuta antes C01-bis."
  exit 1
}
command -v btrfs >/dev/null 2>&1 || {
  echo "ERROR: falta btrfs-progs."
  exit 1
}

FSTYPE="$("${SUDO[@]}" findmnt -no FSTYPE --target "$LAB" 2>/dev/null || true)"
echo "== filesystem de $LAB: ${FSTYPE:-desconocido} =="
if [ "$FSTYPE" != "btrfs" ]; then
  echo "ERROR: el laboratorio no esta en btrfs. No convierto nada."
  exit 1
fi

echo "== cerrando el wineserver del cliente =="
"${AS_U[@]}" env HOME="/home/$U" WINEPREFIX="$PREFIX" WINEARCH=win64 \
  wineserver -k 2>/dev/null || true

echo
if "${SUDO[@]}" btrfs subvolume show "$LAB" >/dev/null 2>&1; then
  echo "== $LAB ya es subvolumen =="
  if "${SUDO[@]}" btrfs subvolume show "$GOLDEN" >/dev/null 2>&1; then
    echo "== ya existe $GOLDEN; no hay nada que hacer =="
    echo "Para rehacerlo: sudo btrfs subvolume delete $GOLDEN y repite este script."
  else
    echo "== creando copia dorada read-only =="
    "${SUDO[@]}" btrfs subvolume snapshot -r "$LAB" "$GOLDEN"
  fi
else
  if "${SUDO[@]}" btrfs subvolume show "$GOLDEN" >/dev/null 2>&1; then
    echo "ERROR: existe $GOLDEN pero $LAB no es subvolumen. Estado ambiguo."
    echo "Revisa los dos antes de seguir; no convierto nada."
    exit 1
  fi
  echo "== convirtiendo $LAB en subvolumen =="
  if [ -e "$OLD" ] || "${SUDO[@]}" test -e "$OLD"; then
    echo "ERROR: ya existe $OLD. Revisa el estado antes de repetir."
    exit 1
  fi
  MODE="$("${SUDO[@]}" stat -c '%a' "$LAB")"
  "${SUDO[@]}" mv "$LAB" "$OLD"
  "${SUDO[@]}" btrfs subvolume create "$LAB"
  "${SUDO[@]}" cp -a --reflink=auto "$OLD/." "$LAB/"
  "${SUDO[@]}" chown -R "$U:$U" "$LAB"
  "${SUDO[@]}" chmod "$MODE" "$LAB"
  echo "copia antigua conservada en $OLD (borrala cuando compruebes que todo va)"
  echo "== creando copia dorada read-only =="
  "${SUDO[@]}" btrfs subvolume snapshot -r "$LAB" "$GOLDEN"
fi

echo
echo "== resultado =="
"${SUDO[@]}" btrfs subvolume show "$LAB" | head -n 12
echo
"${SUDO[@]}" btrfs subvolume show "$GOLDEN" | head -n 12
echo
echo "OK. Para volver a esta copia si algo se rompe: bash tools/c01bis/85-reset.sh"
