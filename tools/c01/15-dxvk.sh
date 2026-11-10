#!/usr/bin/env bash
# C01 - Instala DXVK (d3d8/d3d9/dxgi) en el prefijo.
# La primera vez usa Internet; despues reutiliza la cache local (~/metin2lab/wine/dxvk).
# Uso: bash tools/c01/15-dxvk.sh
set -euo pipefail

BASE="$HOME/metin2lab/wine"
PREFIX="$BASE/prefix"
CACHE="$BASE/dxvk"

[ -d "$PREFIX" ] || { echo "ERROR: ejecuta antes 10-prefix.sh"; exit 1; }

mkdir -p "$CACHE"

DIR=$(find "$CACHE" -maxdepth 1 -mindepth 1 -type d -name 'dxvk-*' 2>/dev/null | sort -V | tail -n1 || true)

if [ -z "${DIR:-}" ]; then
  command -v curl >/dev/null 2>&1 || { echo "ERROR: falta curl y no hay DXVK en cache"; exit 1; }

  if [ -z "${DXVK_URL:-}" ]; then
    echo "== no hay DXVK en cache; buscando la ultima version en GitHub =="
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
else
  echo "== DXVK en cache: $DIR (sin Internet) =="
fi

[ -n "${DIR:-}" ] || { echo "ERROR: no encuentro la carpeta dxvk-*"; exit 1; }

# Arquitectura real del prefijo. Si no se puede leer, asumimos win64 (Wine 10+).
ARCH=win64
if grep -q '^#arch=win32' "$PREFIX/system.reg" 2>/dev/null; then ARCH=win32; fi
echo "== prefijo: $ARCH =="

SYS32="$PREFIX/drive_c/windows/system32"
SYSWOW="$PREFIX/drive_c/windows/syswow64"

install_dll() {
  local dll="$1" src="$2" dst="$3"
  [ -f "$src/$dll" ] || return 0
  cp -f "$src/$dll" "$dst/$dll"
  echo "  $dll -> ${dst#"$PREFIX/drive_c/"}"
}

echo "== copiando DLLs a la carpeta que le toca =="
[ -f "$DIR/x32/d3d9.dll" ] || { echo "ERROR: falta $DIR/x32/d3d9.dll"; exit 1; }
if [ "$ARCH" = "win64" ] && [ -d "$SYSWOW" ]; then
  [ -f "$DIR/x64/d3d9.dll" ] || { echo "ERROR: falta $DIR/x64/d3d9.dll"; exit 1; }
  for d in d3d8 d3d9 dxgi; do
    install_dll "$d.dll" "$DIR/x32" "$SYSWOW"
    install_dll "$d.dll" "$DIR/x64" "$SYS32"
  done
else
  # Prefijo puro de 32 bits (o win64 sin syswow64): todo a system32.
  for d in d3d8 d3d9 dxgi; do
    install_dll "$d.dll" "$DIR/x32" "$SYS32"
  done
fi

echo "== fijando overrides (native,builtin) =="
for d in d3d8 d3d9 dxgi; do
  WINEPREFIX="$PREFIX" WINEARCH="$ARCH" \
    wine reg add 'HKCU\Software\Wine\DllOverrides' /v "$d" /d 'native,builtin' /f >/dev/null
done
WINEPREFIX="$PREFIX" WINEARCH="$ARCH" wineserver -w || true

echo "== comprobacion =="
for d in d3d8 d3d9 dxgi; do
  if [ -f "$SYS32/$d.dll" ]; then ls -l "$SYS32/$d.dll"; fi
  if [ -f "$SYSWOW/$d.dll" ]; then ls -l "$SYSWOW/$d.dll"; fi
done
if [ -f "$SYS32/d3d9.dll" ]; then sha256sum "$SYS32/d3d9.dll"; fi
if [ -f "$SYSWOW/d3d9.dll" ]; then sha256sum "$SYSWOW/d3d9.dll"; fi

echo
echo "OK. Siguiente: bash tools/c01/16-verify-dxvk.sh"
