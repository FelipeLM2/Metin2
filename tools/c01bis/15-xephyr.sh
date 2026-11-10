#!/usr/bin/env bash
# C01-bis - Arranca Xephyr: un servidor X anidado que solo muestra las ventanas
# del cliente. Xephyr corre dentro de un netns vacio (solo lo), asi un fallo
# suyo no tiene red. El usuario metin2 no ve el escritorio real, solo este
# display. El juego se conecta a :7 por el socket Unix de /tmp, que si cruza
# netns.
# Uso: bash tools/c01bis/15-xephyr.sh
#      SIN_NETNS=1 bash tools/c01bis/15-xephyr.sh   # solo depuracion
set -euo pipefail

NS=m2xephyr
DISP=:7
GEOM="${GEOM:-1920x1080}"
SOCK="/tmp/.X11-unix/X${DISP#:}"
LOCK="/tmp/.X${DISP#:}-lock"
LOGFILE="${LOGFILE:-/tmp/xephyr-c01bis.log}"
SIN_NETNS="${SIN_NETNS:-0}"

# Xephyr pinta en la pantalla real, asi que corre como el usuario de la sesion,
# no como metin2. El netns lo pone root; despues se baja a este usuario.
REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_UID="$(id -u "$REAL_USER")"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
DISP_VAL="${DISPLAY:-:0}"
XDG_VAL="${XDG_RUNTIME_DIR:-/run/user/$REAL_UID}"
XAUTH_VAL="${XAUTHORITY:-}"
if [ -z "$XAUTH_VAL" ] && [ -d "$XDG_VAL" ]; then
  XAUTH_VAL="$(find "$XDG_VAL" -maxdepth 1 -name 'xauth_*' 2>/dev/null | head -n 1 || true)"
fi
[ -n "$XAUTH_VAL" ] || XAUTH_VAL="$REAL_HOME/.Xauthority"

ENVV=(HOME="$REAL_HOME" DISPLAY="$DISP_VAL" XDG_RUNTIME_DIR="$XDG_VAL")
if [ -n "$XAUTH_VAL" ] && [ -f "$XAUTH_VAL" ]; then
  ENVV+=(XAUTHORITY="$XAUTH_VAL")
fi

display_ok() {
  [ -S "$SOCK" ] || return 1
  if command -v xdpyinfo >/dev/null 2>&1; then
    xdpyinfo -display "$DISP" >/dev/null 2>&1
  elif command -v xset >/dev/null 2>&1; then
    DISPLAY="$DISP" xset q >/dev/null 2>&1
  else
    return 0
  fi
}

netns_exists() {
  ip netns list | awk '{print $1}' | grep -qx "$NS"
}

netns_inode() {
  sudo ip netns exec "$NS" readlink /proc/self/ns/net
}

proc_inode() {
  readlink "/proc/$1/ns/net" 2>/dev/null || true
}

xephyr_pids() {
  pgrep -x Xephyr -a 2>/dev/null \
    | awk -v pat="Xephyr $DISP" 'index($0, pat) {print $1}' \
    || true
}

xephyr_pid() {
  xephyr_pids | head -n 1
}

kill_old_xephyr() {
  echo "== reiniciando Xephyr: el que habia no estaba en $NS =="
  PIDS="$(xephyr_pids)"
  if [ -n "$PIDS" ]; then
    # shellcheck disable=SC2086
    sudo kill $PIDS 2>/dev/null || true
  fi
  for _ in 1 2 3 4 5; do
    [ -z "$(xephyr_pids)" ] && break
    sleep 1
  done
  if [ -z "$(xephyr_pids)" ]; then
    sudo rm -f "$LOCK" "$SOCK" 2>/dev/null || true
  fi
}

command -v Xephyr >/dev/null 2>&1 || {
  echo "ERROR: falta Xephyr."
  echo "Instalalo con: sudo pacman -S xorg-server-xephyr"
  exit 1
}

if [ "$SIN_NETNS" = "1" ]; then
  echo "AVISO: SIN_NETNS=1: Xephyr correra SIN jaula. Solo para depurar."
else
  if netns_exists; then
    echo "== jaula $NS ya existe =="
  else
    echo "== creando jaula $NS (solo lo, sin red) =="
    sudo ip netns add "$NS"
  fi
  sudo ip netns exec "$NS" ip link set lo up
  sudo ip netns exec "$NS" sh -c \
    'echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6; echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6' \
    2>/dev/null || true

  # Aunque m2xephyr no tenga interfaces, nss-resolve podria preguntar al
  # systemd-resolved del host por D-Bus y sacar nombres por DNS. Se cierra
  # igual que en la jaula del juego: hosts solo por /etc/hosts.
  echo "== cerrando DNS en $NS =="
  sudo mkdir -p "/etc/netns/$NS"
  sudo sh -c ": > /etc/netns/$NS/resolv.conf"
  if [ -f /etc/nsswitch.conf ] && grep -qE '^[[:space:]]*hosts:' /etc/nsswitch.conf; then
    sed -E 's/^[[:space:]]*hosts:.*/hosts:      files/' /etc/nsswitch.conf \
      | sudo tee "/etc/netns/$NS/nsswitch.conf" >/dev/null
  else
    printf 'hosts:      files\n' \
      | sudo tee "/etc/netns/$NS/nsswitch.conf" >/dev/null
  fi
fi

if display_ok; then
  PID="$(xephyr_pid)"
  if [ "$SIN_NETNS" = "1" ]; then
    echo "Xephyr ya esta en $DISP (sin jaula, SIN_NETNS=1)"
    exit 0
  fi
  if [ -n "$PID" ] && [ "$(proc_inode "$PID")" = "$(netns_inode)" ]; then
    echo "Xephyr ya esta en $DISP dentro de $NS"
    exit 0
  fi
  kill_old_xephyr
elif [ -z "$(xephyr_pid)" ]; then
  # Socket o lock huerfano de un cierre brusco: Xephyr no arrancaria.
  sudo rm -f "$LOCK" "$SOCK" 2>/dev/null || true
fi

echo "== arrancando Xephyr en $DISP ($GEOM, fullscreen) =="
# -ac desactiva el control de acceso SOLO del display :7. El escritorio real
# sigue siendo :0 y no se abre. Asi metin2 puede pintar sin cookie y sin ver
# nada del usuario real.
if [ "$SIN_NETNS" = "1" ]; then
  if [ "$(id -un)" = "$REAL_USER" ]; then
    nohup env "${ENVV[@]}" Xephyr "$DISP" -screen "$GEOM" -fullscreen -ac -noreset \
      -title "Metin2 (jaula C01-bis)" >"$LOGFILE" 2>&1 &
  else
    nohup sudo -u "$REAL_USER" env "${ENVV[@]}" Xephyr "$DISP" \
      -screen "$GEOM" -fullscreen -ac -noreset \
      -title "Metin2 (jaula C01-bis)" >"$LOGFILE" 2>&1 &
  fi
else
  nohup sudo ip netns exec "$NS" \
    sudo -u "$REAL_USER" env "${ENVV[@]}" \
    Xephyr "$DISP" -screen "$GEOM" -fullscreen -ac -noreset \
    -title "Metin2 (jaula C01-bis)" >"$LOGFILE" 2>&1 &
fi

for _ in $(seq 1 15); do
  sleep 1
  if display_ok; then
    PID="$(xephyr_pid)"
    if [ "$SIN_NETNS" = "1" ]; then
      echo "OK: Xephyr listo en $DISP (sin jaula, SIN_NETNS=1)"
      echo "Para sacar el raton de la ventana: Ctrl+Shift"
      exit 0
    fi
    if [ -z "$PID" ]; then
      echo "AVISO: $DISP responde pero no veo el proceso Xephyr; sigo esperando"
    elif [ "$(proc_inode "$PID")" = "$(netns_inode)" ]; then
      echo "OK: Xephyr listo en $DISP dentro de $NS"
      echo "Para sacar el raton de la ventana: Ctrl+Shift"
      exit 0
    else
      echo "ERROR: Xephyr arranco fuera de $NS. No sigas."
      exit 1
    fi
  fi
done

echo "ERROR: Xephyr no respondio. Mira $LOGFILE"
echo "Si sospechas del netns, prueba: SIN_NETNS=1 bash tools/c01bis/15-xephyr.sh"
exit 1
