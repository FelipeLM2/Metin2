#!/usr/bin/env bash
# C01-bis - Ejecuta un comando con el bus del sistema fuera de su vista.
#
# Lo llaman 15-xephyr.sh y 30-run-client.sh como root, ya dentro del netns y
# de un mount namespace (unshare --mount). Enmascara el socket del bus con
# /dev/null; el montaje vive solo en ese namespace y desaparece al terminar.
# No modifica el host, no instala nada y no necesita bubblewrap.
#
# Uso (desde los otros scripts, nunca a mano):
#   19-sin-bus.sh <usuario> <comando...>
#
# SIN_BUS=1 19-sin-bus.sh ...   # no enmascara (solo depuracion)
#
# Si /run/dbus/system_bus_socket no existe, no hay nada que enmascarar: el
# proceso simplemente no tiene bus del sistema.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || {
  echo "ERROR: 19-sin-bus.sh necesita root (lo invocan 15 y 30 con sudo)." >&2
  exit 1
}
[ "$#" -ge 2 ] || {
  echo "Uso: $0 <usuario> <comando...>" >&2
  exit 1
}

U="$1"
shift
SOCK=/run/dbus/system_bus_socket
SIN_BUS="${SIN_BUS:-0}"

if [ "$SIN_BUS" = "1" ]; then
  echo "AVISO: SIN_BUS=1: el bus del sistema queda visible (solo depuracion)." >&2
elif [ -S "$SOCK" ]; then
  if ! mount --bind /dev/null "$SOCK" 2>/dev/null || [ -S "$SOCK" ]; then
    echo "ERROR: no pude enmascarar $SOCK" >&2
    exit 1
  fi
  echo "OK: bus del sistema enmascarado para $U (mount ns)." >&2
elif [ -e "$SOCK" ]; then
  # Ya enmascarado por una invocacion anterior en este namespace.
  echo "OK: bus del sistema ya enmascarado (mount ns)." >&2
else
  echo "OK: no hay socket de bus del sistema que enmascarar." >&2
fi

# sudo aqui solo baja privilegios: sigue en el mismo mount namespace.
exec sudo -u "$U" -- "$@"
