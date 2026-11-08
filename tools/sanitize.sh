#!/usr/bin/env bash
# Redacta secretos tipicos en las salidas antes de subirlas al repo publico.
#
#   tools/sanitize.sh salidas/2026-11-07-b01-recon-eterpack.txt
#
# No es infalible: SIEMPRE revisar con `git diff` antes del commit.
# Pensado para GNU sed (CachyOS / Linux). En FreeBSD cambia `sed -i` por `sed -i ''`.

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "uso: $0 <archivo> [archivo...]" >&2
  exit 1
fi

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "no existe: $f" >&2
    continue
  fi

  sed -i -E \
    -e "s/(-p[[:space:]]*')([^']*)(')/\1<REDACTADO>\3/g" \
    -e "s/(-p[[:space:]]*\")([^\"]*)(\")/\1<REDACTADO>\3/g" \
    -e "s/(--password[= ][[:space:]]*)[^[:space:]]+/\1<REDACTADO>/g" \
    -e "s/(PASSWORD[[:space:]]*\([[:space:]]*')[^']*(')/\1<REDACTADO>\2/gI" \
    -e "s/(SQL_[A-Z_]+[[:space:]]*=[[:space:]]*\").*/\1<REDACTADO>\"/g" \
    -e "s/((PASSWORD|PASSWD|SECRET)[A-Z_]*[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1<REDACTADO>/gI" \
    "$f"

  echo "sanitizado: $f"
done

echo
echo "Revisa antes de commitear:  git diff salidas/"
