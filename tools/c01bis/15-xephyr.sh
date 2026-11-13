#!/usr/bin/env bash
# C01-bis - Arranca Xephyr: un servidor X anidado que solo muestra las ventanas
# del cliente. Xephyr corre dentro de un netns vacio (solo lo), asi un fallo
# suyo no tiene red. El usuario metin2 no ve el escritorio real, solo este
# display. El juego se conecta a :7 por el socket Unix de /tmp, que si cruza
# netns.
# Uso: bash tools/c01bis/15-xephyr.sh                  # ventana (por defecto)
#      HOST_GRAB=1 bash tools/c01bis/15-xephyr.sh      # ventana + captura raton/teclado
#      FULLSCREEN=1 bash tools/c01bis/15-xephyr.sh     # pantalla completa opcional
#      SIN_NETNS=1 bash tools/c01bis/15-xephyr.sh      # solo depuracion
#      SIN_BUS=1 bash tools/c01bis/15-xephyr.sh        # no ocultar el bus (depurar)
#      XEPHYR_BIN=/ruta/a/Xephyr bash ...             # usar otro binario
# Si existe ~/.local/bin/Xephyr (14-xephyr-warp.sh), se usa ese: es el que
# reenvia el warp del puntero al servidor real y arregla la camara.
# Para cerrarlo: bash tools/c01bis/16-xephyr-stop.sh
set -euo pipefail

NS=m2xephyr
DISP=:7
GEOM="${GEOM:-1920x1080}"
FULLSCREEN="${FULLSCREEN:-0}"
# Por defecto Xephyr NO captura el raton ni el teclado del host. El juego usa
# un puntero relativo: si el cursor del host se escapa de la ventana, Xephyr
# deja de recibir movimiento y la camara da saltos. Con HOST_GRAB=1 si captura
# mientras juegas; Ctrl+Shift suelta la captura y 16-xephyr-stop.sh sigue
# siendo la salida segura.
HOST_GRAB="${HOST_GRAB:-0}"
SOCK="/tmp/.X11-unix/X${DISP#:}"
LOCK="/tmp/.X${DISP#:}-lock"
LOGFILE="${LOGFILE:-/tmp/xephyr-c01bis.log}"
SIN_NETNS="${SIN_NETNS:-0}"
# Por defecto se oculta el bus del sistema a Xephyr (19-sin-bus.sh). SIN_BUS=1
# lo deja visible; solo para depurar un fallo del montaje.
SIN_BUS="${SIN_BUS:-0}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

print_ready() {
  echo "$1"
  if [ "$FULLSCREEN" = "1" ]; then
    echo "Pantalla completa. Para salir: bash tools/c01bis/16-xephyr-stop.sh (o Ctrl+Alt+F3)."
  elif [ "$HOST_GRAB" = "1" ]; then
    echo "Modo ventana CON captura: al jugar, el raton queda dentro de Xephyr."
    echo "Ctrl+Shift lo suelta; para cerrar: bash tools/c01bis/16-xephyr-stop.sh"
  else
    echo "Modo ventana: Alt+Tab funciona; Xephyr no captura teclado ni raton."
    echo "Para cerrar Xephyr: bash tools/c01bis/16-xephyr-stop.sh"
  fi
  if [ "$CAM_FIX" = "1" ]; then
    echo "Camara: Xephyr parcheado (warp real). Arrastra con el boton derecho."
  else
    echo "Camara: si da saltos, compila el Xephyr parcheado:"
    echo "  bash tools/c01bis/14-xephyr-warp.sh"
  fi
}

# Prefiere el Xephyr parcheado de 14-xephyr-warp.sh. El de pacman solo mueve
# su puntero interno y ahi la camara del cliente da saltos.
XEPHYR_BIN="${XEPHYR_BIN:-$REAL_HOME/.local/bin/Xephyr}"
if [ ! -x "$XEPHYR_BIN" ]; then
  XEPHYR_BIN="$(command -v Xephyr 2>/dev/null || true)"
fi
if [ -z "$XEPHYR_BIN" ]; then
  echo "ERROR: falta Xephyr."
  echo "Instalalo con: sudo pacman -S xorg-server-xephyr"
  echo "O compila el parcheado: bash tools/c01bis/14-xephyr-warp.sh"
  exit 1
fi
CAM_FIX=0
if [ "$XEPHYR_BIN" = "$REAL_HOME/.local/bin/Xephyr" ]; then
  CAM_FIX=1
fi

# El cierre del bus usa unshare --mount (util-linux) y solo funciona como root,
# dentro del netns. Si no esta disponible, mejor parar que arrancar sin el.
if [ "$SIN_NETNS" != "1" ] && [ "$SIN_BUS" != "1" ]; then
  command -v unshare >/dev/null 2>&1 || {
    echo "ERROR: falta unshare (paquete util-linux)."
    exit 1
  }
  if ! sudo unshare --mount --propagation private true 2>/dev/null; then
    echo "ERROR: 'unshare --mount' no funciona en este sistema."
    echo "No arranco Xephyr sin cerrar el bus. Para depurar: SIN_BUS=1 bash $0"
    exit 1
  fi
fi

if [ "$SIN_NETNS" = "1" ]; then
  echo "AVISO: SIN_NETNS=1: Xephyr correra SIN jaula y sin cerrar el bus. Solo para depurar."
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
    echo "Para cambiar de modo o de captura (ventana/pantalla completa/raton):"
    echo "  bash tools/c01bis/16-xephyr-stop.sh"
    exit 0
  fi
  kill_old_xephyr
elif [ -z "$(xephyr_pid)" ]; then
  # Socket o lock huerfano de un cierre brusco: Xephyr no arrancaria.
  sudo rm -f "$LOCK" "$SOCK" 2>/dev/null || true
fi

if [ "$FULLSCREEN" = "1" ]; then
  MODE="pantalla completa (FULLSCREEN=1)"
  XARGS=(-fullscreen)
else
  MODE="ventana"
  XARGS=()
fi
# -resizeable: la ventana se puede redimensionar como cualquier otra.
# -nolisten tcp: no abre puerto TCP; dentro de m2xephyr no habria red igualmente.
# -ac desactiva el control de acceso SOLO del display :7. El escritorio real
# sigue siendo :0 y no se abre. Asi metin2 puede pintar sin cookie y sin ver
# nada del usuario real.
# -no-host-grab (por defecto): Xephyr no secuestra el teclado/raton del host.
# Con HOST_GRAB=1 se omite y si los captura mientras hay un grab del juego.
XARGS+=(-screen "$GEOM" -ac -noreset -resizeable -nolisten tcp
        -title "Metin2 (jaula C01-bis)")
if [ "$HOST_GRAB" = "1" ]; then
  echo "AVISO: HOST_GRAB=1: Xephyr capturara el raton/teclado al jugar."
  echo "       Ctrl+Shift suelta la captura; 16-xephyr-stop.sh es la salida segura."
else
  XARGS+=(-no-host-grab)
fi

echo "== arrancando Xephyr en $DISP ($GEOM, $MODE) =="
echo "   binario: $XEPHYR_BIN"
if [ "$SIN_NETNS" = "1" ]; then
  echo "   bus del sistema: visible (SIN_NETNS=1, solo depuracion)"
elif [ "$SIN_BUS" = "1" ]; then
  echo "   bus del sistema: visible (SIN_BUS=1, solo depuracion)"
else
  echo "   bus del sistema: enmascarado (mount ns)"
fi
if [ "$FULLSCREEN" = "1" ]; then
  echo "AVISO: pantalla completa. Si algo se bloquea, abre otra TTY (Ctrl+Alt+F3)"
  echo "       y ejecuta: bash tools/c01bis/16-xephyr-stop.sh"
fi
if [ "$SIN_NETNS" = "1" ]; then
  if [ "$(id -un)" = "$REAL_USER" ]; then
    nohup env -u DBUS_SYSTEM_BUS_ADDRESS "${ENVV[@]}" \
      "$XEPHYR_BIN" "$DISP" "${XARGS[@]}" >"$LOGFILE" 2>&1 &
  else
    nohup sudo -u "$REAL_USER" env -u DBUS_SYSTEM_BUS_ADDRESS "${ENVV[@]}" \
      "$XEPHYR_BIN" "$DISP" "${XARGS[@]}" >"$LOGFILE" 2>&1 &
  fi
else
  nohup sudo ip netns exec "$NS" \
    env SIN_BUS="$SIN_BUS" \
    unshare --mount --propagation private \
    bash "$HERE/19-sin-bus.sh" "$REAL_USER" \
    env -u DBUS_SYSTEM_BUS_ADDRESS "${ENVV[@]}" \
    "$XEPHYR_BIN" "$DISP" "${XARGS[@]}" >"$LOGFILE" 2>&1 &
fi

for _ in $(seq 1 15); do
  sleep 1
  if display_ok; then
    PID="$(xephyr_pid)"
    if [ "$SIN_NETNS" = "1" ]; then
      print_ready "OK: Xephyr listo en $DISP (sin jaula, SIN_NETNS=1)"
      exit 0
    fi
    if [ -z "$PID" ]; then
      echo "AVISO: $DISP responde pero no veo el proceso Xephyr; sigo esperando"
    elif [ "$(proc_inode "$PID")" = "$(netns_inode)" ]; then
      print_ready "OK: Xephyr listo en $DISP dentro de $NS"
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
