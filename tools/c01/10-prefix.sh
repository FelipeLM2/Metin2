#!/usr/bin/env bash
# C01 - Crea el prefijo Wine de 32 bits, quita Z: y copia el cliente con el pack.
# Uso: bash tools/c01/10-prefix.sh
set -euo pipefail

BASE="$HOME/metin2lab/wine"
PREFIX="$BASE/prefix"
SRC="$HOME/metin2lab/tmp4/Client/Client"
PACK="$HOME/metin2lab/work/b04"
GAME="$PREFIX/drive_c/Games/Metin2"

echo "== comprobaciones =="
[ -d "$SRC" ] || { echo "ERROR: no existe $SRC"; exit 1; }
[ -f "$PACK/root.eix" ] || { echo "ERROR: falta $PACK/root.eix"; exit 1; }
[ -f "$PACK/root.epk" ] || { echo "ERROR: falta $PACK/root.epk"; exit 1; }
command -v wine >/dev/null 2>&1 || { echo "ERROR: wine no instalado"; exit 1; }

eix_size=$(stat -c '%s' "$PACK/root.eix")
epk_size=$(stat -c '%s' "$PACK/root.epk")
echo "root.eix=$eix_size  root.epk=$epk_size"
[ "$eix_size" = "17292" ] || { echo "ERROR: root.eix no mide 17292"; exit 1; }
[ "$epk_size" = "520704" ] || { echo "ERROR: root.epk no mide 520704"; exit 1; }

mkdir -p "$BASE/logs"

if [ ! -d "$PREFIX" ]; then
  echo "== creando prefijo win32 (puede tardar) =="
  WINEARCH=win32 WINEPREFIX="$PREFIX" WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u
  WINEARCH=win32 WINEPREFIX="$PREFIX" wineserver -w || true
else
  echo "== el prefijo ya existe, no se recrea =="
fi

echo "== quitando unidades ajenas a C: (incluida Z: -> /) =="
for d in "$PREFIX"/dosdevices/[a-z]:; do
  [ -L "$d" ] || [ -e "$d" ] || continue
  [ "$(basename "$d")" = "c:" ] && continue
  echo "  quito $(basename "$d") -> $(readlink "$d" 2>/dev/null || echo '?')"
  rm -f "$d"
done
echo "unidades ahora:"
ls -la "$PREFIX/dosdevices"

echo "== copiando cliente a $GAME =="
mkdir -p "$GAME"
cp -a "$SRC/." "$GAME/"

echo "== instalando pack parcheado =="
mkdir -p "$GAME/pack"
cp -f "$PACK/root.eix" "$GAME/pack/root.eix"
cp -f "$PACK/root.epk" "$GAME/pack/root.epk"
stat -c '%s %n' "$GAME/pack/root.eix" "$GAME/pack/root.epk"
sha256sum "$GAME/pack/root.eix" "$GAME/pack/root.epk"

echo "== ejecutables en la raiz del cliente =="
find "$GAME" -maxdepth 1 -type f -iname '*.exe' -printf '  %f (%s bytes)\n' || true

echo
echo "OK. Siguiente: bash tools/c01/15-dxvk.sh"
