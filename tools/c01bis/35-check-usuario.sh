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
echo "-- intento de leer $HOME (debe fallar):"
if sudo -u "$U" test -r "$HOME"; then
  echo "PELIGRO: $U puede leer $HOME"
else
  echo "OK: sin acceso a $HOME"
fi

echo
echo "== laboratorio =="
sudo stat -c '%A %U %n' "$HOME_U" "$HOME_U/metin2lab/wine/prefix" 2>/dev/null

echo
echo "== Xephyr en su propia jaula (m2xephyr, solo lo) =="
if ! ip netns list | awk '{print $1}' | grep -qx m2xephyr; then
  echo "AVISO: no existe m2xephyr; Xephyr corre fuera de jaula (¿SIN_NETNS=1?)"
else
  echo "-- interfaces:"
  sudo ip netns exec m2xephyr ip -brief addr
  echo "-- rutas (debe estar vacio):"
  sudo ip netns exec m2xephyr ip route
  if sudo ip netns exec m2xephyr ip route | grep -q .; then
    echo "PELIGRO: m2xephyr tiene rutas; revisa la jaula"
  else
    echo "OK: m2xephyr sin rutas"
  fi
  if sudo ip netns exec m2xephyr getent hosts example.com >/dev/null 2>&1; then
    echo "PELIGRO: m2xephyr resuelve nombres (DNS abierto)"
  else
    echo "OK: m2xephyr sin DNS"
  fi
  EXTRA=$(sudo ip netns exec m2xephyr ip -brief link \
    | awk '$1 != "lo" {print $1}')
  if [ -n "$EXTRA" ]; then
    echo "PELIGRO: m2xephyr tiene interfaces de red: $EXTRA"
  else
    echo "OK: m2xephyr solo tiene lo"
  fi

  echo "-- procesos dentro (deberia estar Xephyr):"
  PIDS=$(sudo ip netns pids m2xephyr 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    # shellcheck disable=SC2086
    ps -o pid,user,comm -p $PIDS 2>/dev/null || true
    # shellcheck disable=SC2086
    if ps -o comm= -p $PIDS 2>/dev/null | grep -qx 'Xephyr'; then
      echo "OK: Xephyr corre dentro de m2xephyr"
    else
      echo "AVISO: no veo Xephyr dentro de m2xephyr"
    fi
  else
    echo "(no hay procesos en m2xephyr; si el juego esta abierto, algo falla)"
  fi

  XPID=$(pgrep -x Xephyr -a 2>/dev/null \
    | awk 'index($0, "Xephyr :7") {print $1; exit}' || true)
  if [ -n "$XPID" ]; then
    XNS=$(readlink "/proc/$XPID/ns/net" 2>/dev/null || true)
    MNS=$(sudo ip netns exec m2xephyr readlink /proc/self/ns/net 2>/dev/null || true)
    if [ "$XNS" = "$MNS" ]; then
      echo "OK: el Xephyr de :7 esta en m2xephyr"
    else
      echo "PELIGRO: el Xephyr de :7 esta FUERA de m2xephyr"
    fi
  else
    echo "(Xephyr :7 no esta corriendo)"
  fi
fi

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
