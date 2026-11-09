#!/usr/bin/env bash
# C01 - Instala DXVK (d3d9/dxgi de 32 bits) en el prefijo. Esto SI usa Internet.
# Uso: bash tools/c01/15-dxvk.sh
set -euo pipefail

BASE="$HOME/metin2lab/wine"
PREFIX="$BASE/prefix"
CACHE="$BASE/dxvk"

[ -d "$PREFIX" ] || { echo "ERROR: ejecuta antes 10-prefix.sh"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: falta curl"; exit 1; }

mkdir -p "$CACHE"

if [ -z "${DXVK_URL:-}" ]; then
  echo "== buscando la ultima version de DXVK en GitHub =="
  DXVK_URL=$(curl -fsSL https://api.github.com/repos/doitsujin/dxvk/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*\.tar\.gz"' \
    | head -n1 \
    | sed 's/.*"\(https[^"]*\)"/\1/')
fi

[ -n "${DXVK_URL:-}" ] || {
  echo "ERROR: no pude obtener la URL de DXVK."
  echo "Define DXVK_URL, por ejemplo:"
  echo "  DXVK_URL=https://github.com/doitsujin/dxvk/releases/download/v2.7.1/dxvk-2.7.1.tar.gz bash tools/c01/15-dxvk.sh"
  exit 1
}
echo "URL: $DXVK_URL"

TAR="$CACHE/dxvk.tar.gz"
if [ ! -s "$TAR" ]; then
  echo "== descargando =="
  curl -fL "$DXVK_URL" -o "$TAR"
fi

rm -rf "$CACHE"/dxvk-[0-9]*
tar -xzf "$TAR" -C "$CACHE"
DIR=$(find "$CACHE" -maxdepth 1 -mindepth 1 -type d -name 'dxvk-*' | sort -V | tail -n1)
[ -n "$DIR" ] || { echo "ERROR: no encuentro la carpeta dxvk-*"; exit 1; }
echo "DXVK: $DIR"

[ -f "$DIR/x32/d3d9.dll" ] || { echo "ERROR: falta x32/d3d9.dll"; exit 1; }
[ -f "$DIR/x32/dxgi.dll" ] || { echo "ERROR: falta x32/dxgi.dll"; exit 1; }

echo "== copiando DLLs de 32 bits al prefijo =="
cp -f "$DIR/x32/d3d9.dll" "$PREFIX/drive_c/windows/system32/d3d9.dll"
cp -f "$DIR/x32/dxgi.dll" "$PREFIX/drive_c/windows/system32/dxgi.dll"

echo "== fijando overrides (native,builtin) =="
WINEPREFIX="$PREFIX" WINEARCH=win32 wine reg add 'HKCU\Software\Wine\DllOverrides' /v d3d9 /d 'native,builtin' /f
WINEPREFIX="$PREFIX" WINEARCH=win32 wine reg add 'HKCU\Software\Wine\DllOverrides' /v dxgi /d 'native,builtin' /f
WINEPREFIX="$PREFIX" WINEARCH=win32 wineserver -w || true

echo "== comprobacion =="
ls -l "$PREFIX/drive_c/windows/system32/d3d9.dll" "$PREFIX/drive_c/windows/system32/dxgi.dll"
sha256sum "$PREFIX/drive_c/windows/system32/d3d9.dll" "$PREFIX/drive_c/windows/system32/dxgi.dll"

echo
echo "OK. Siguiente: bash tools/c01/20-netns-up.sh"
