#!/usr/bin/env bash
# C01 - Solo lectura: comprueba arquitectura del prefijo, DLLs de DXVK y que
# API de Direct3D importa el cliente.
# Uso: bash tools/c01/16-verify-dxvk.sh
set -uo pipefail

BASE="$HOME/metin2lab/wine"
PREFIX="$BASE/prefix"
GAME="$PREFIX/drive_c/Games/Metin2"
SYS32="$PREFIX/drive_c/windows/system32"
SYSWOW="$PREFIX/drive_c/windows/syswow64"
EXE="$GAME/metin2client.exe"

[ -d "$PREFIX" ] || { echo "ERROR: no existe $PREFIX"; exit 1; }

echo "== arquitectura del prefijo =="
grep -m1 '^#arch=' "$PREFIX/system.reg" 2>/dev/null || echo "(no encuentro #arch en system.reg)"

echo
echo "== carpetas de DLLs =="
[ -d "$SYS32" ] && echo "system32: si" || echo "system32: NO"
[ -d "$SYSWOW" ] && echo "syswow64: si" || echo "syswow64: NO"

echo
echo "== d3d8 / d3d9 / dxgi en el prefijo =="
for d in d3d8 d3d9 dxgi; do
  for dir in "$SYS32" "$SYSWOW"; do
    f="$dir/$d.dll"
    if [ -f "$f" ]; then
      printf '%-6s %10s  %s\n' "$d" "$(stat -c %s "$f")" "${f#"$PREFIX/drive_c/"}"
    fi
  done
done

echo
echo "== overrides registrados =="
WINEPREFIX="$PREFIX" wine reg query 'HKCU\Software\Wine\DllOverrides' 2>/dev/null \
  | grep -iE 'd3d8|d3d9|dxgi' || echo "(sin overrides para d3d8/d3d9/dxgi)"

echo
echo "== arquitectura del cliente =="
if [ -f "$EXE" ]; then
  if command -v file >/dev/null 2>&1; then
    file "$EXE"
  elif command -v objdump >/dev/null 2>&1; then
    objdump -f "$EXE" 2>/dev/null | grep -iE 'file format|architecture' || true
  else
    echo "(faltan file y objdump)"
  fi
else
  echo "no existe $EXE"
fi

echo
echo "== DLLs que importa el cliente =="
if [ -f "$EXE" ]; then
  if command -v objdump >/dev/null 2>&1; then
    objdump -p "$EXE" 2>/dev/null \
      | sed -n 's/.*DLL Name: //p' \
      | grep -iE 'd3d|dxgi|ddraw' \
      || echo "(no veo d3d/dxgi/ddraw en los imports: puede cargarlos en tiempo de ejecucion)"
  elif command -v strings >/dev/null 2>&1; then
    strings -a "$EXE" 2>/dev/null \
      | grep -ioE 'd3d(8|9)\.dll|dxgi\.dll|ddraw\.dll' | sort -u \
      || echo "(no encuentro d3d/dxgi en las cadenas)"
  else
    echo "(faltan objdump y strings; no se puede inspeccionar el .exe)"
  fi
else
  echo "no existe $EXE"
fi

echo
echo "== pista rapida =="
if [ -f "$SYSWOW/d3d9.dll" ] && [ "$(stat -c %s "$SYSWOW/d3d9.dll")" -gt 1000000 ]; then
  echo "DXVK parece instalado en syswow64 (32 bits), que es lo correcto en win64."
else
  echo "AVISO: syswow64/d3d9.dll no es DXVK; un cliente de 32 bits usaria wined3d."
fi

echo
echo "OK. Siguiente: bash tools/c01/20-netns-up.sh"
