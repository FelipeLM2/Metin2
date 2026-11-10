#!/usr/bin/env bash
# C01-bis - Solo lectura: comprueba que el usuario metin2 esta contenido.
# Complementa a tools/c01/35-check-isolation.sh (que mira la red).
# Uso: bash tools/c01bis/35-check-usuario.sh
set -uo pipefail

U=metin2
HOME_U="/home/$U"
UID_ME=$(id -u)

echo "== identidad y sudo =="
id "$U"
sudo -l -U "$U" 2>&1 | head -n 5

echo
echo "== home del usuario real =="
stat -c '%A %U %n' "$HOME"
echo "-- intento de listar $HOME (debe fallar):"
if sudo -u "$U" ls "$HOME" 2>/dev/null | head -n 1 | grep -q .; then
  echo "PELIGRO: $U puede leer $HOME"
else
  echo "OK: sin acceso a $HOME"
fi

echo
echo "== laboratorio =="
stat -c '%A %U %n' "$HOME_U" "$HOME_U/metin2lab/wine/prefix" 2>/dev/null

echo
echo "== bus de sesion del usuario (debe estar fuera de alcance) =="
if [ -S "/run/user/$UID_ME/bus" ]; then
  if sudo -u "$U" test -r "/run/user/$UID_ME/bus"; then
    echo "PELIGRO: $U puede leer el bus de sesion"
  else
    echo "OK: sin acceso al bus de sesion"
  fi
else
  echo "(no hay bus de sesion en /run/user/$UID_ME)"
fi

echo
echo "== bus del sistema (residual conocido) =="
if sudo -u "$U" test -r /run/dbus/system_bus_socket; then
  echo "AVISO: $U puede leer el bus del sistema; queda como riesgo residual."
else
  echo "OK: sin acceso al bus del sistema"
fi

echo
echo "== audio del usuario (debe estar fuera de alcance) =="
if sudo -u "$U" test -r "/run/user/$UID_ME/pipewire-0"; then
  echo "PELIGRO: $U puede usar el PipeWire del usuario"
else
  echo "OK: sin audio (el juego va en silencio a proposito)"
fi
