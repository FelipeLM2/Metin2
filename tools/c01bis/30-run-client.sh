#!/usr/bin/env bash
# C01-bis - Lanza el cliente como el usuario metin2, dentro de la jaula de red
# y en el display anidado de Xephyr.
# Uso: bash tools/c01bis/30-run-client.sh
#      WINEDEBUG=+winex11 bash tools/c01bis/30-run-client.sh   # traza raton/X11
#      (la traza crece muy rapido: usala solo para pruebas cortas)
set -euo pipefail

NS=metin2lab
DISP=:7
U=metin2
BASE="/home/$U/metin2lab/wine"
PREFIX="$BASE/prefix"
GAME="$PREFIX/drive_c/Games/Metin2"
ULOG="$BASE/logs"
LOG="$HOME/metin2lab/logs/client-$(date +%Y%m%d-%H%M%S).log"
UID_M2=$(id -u "$U")

ip netns list | awk '{print $1}' | grep -qx "$NS" \
  || { echo "ERROR: la jaula $NS no existe. Ejecuta tools/c01/20-netns-up.sh"; exit 1; }
[ -S "/tmp/.X11-unix/X${DISP#:}" ] \
  || { echo "ERROR: Xephyr no esta en $DISP. Ejecuta tools/c01bis/15-xephyr.sh"; exit 1; }
# /home/metin2 es 700: comprobamos como metin2, no como nosotros.
sudo -u "$U" test -d "$GAME" \
  || { echo "ERROR: no existe $GAME. Ejecuta tools/c01bis/10-usuario.sh"; exit 1; }
sudo -u "$U" test -f "$GAME/metin2client.exe" \
  || { echo "ERROR: falta $GAME/metin2client.exe"; exit 1; }

WINE_BIN=$(command -v wine)
mkdir -p "$HOME/metin2lab/logs"
sudo install -d -m 700 -o "$U" -g "$U" "/run/user/$UID_M2"
sudo -u "$U" mkdir -p "$ULOG"
sudo -u "$U" mkdir -p "$GAME/dxvk-logs" "$GAME/dxvk-state"

echo "== lanzando metin2client.exe como $U dentro de $NS, en $DISP =="
echo "log: $LOG"
echo "Cuando aparezca la ventana, entra al juego. Deja esta terminal abierta."
echo

# Si quedo un wineserver del prefijo fuera de la jaula, el cliente podria
# nacer en la red del host. Lo matamos antes de lanzar el de dentro.
sudo -u "$U" env HOME="/home/$U" WINEPREFIX="$PREFIX" WINEARCH=win64 \
  wineserver -k 2>/dev/null || true

# Sin bus de sesion ni cookie de X del usuario real. El display :7 es anonimo
# (-ac) y solo pinta las ventanas de este cliente. El cd va dentro del shell de
# metin2 porque nuestro usuario no puede entrar en /home/metin2.
set +e
sudo ip netns exec "$NS" \
  sudo -u "$U" \
  env -u XAUTHORITY -u DBUS_SESSION_BUS_ADDRESS \
      HOME="/home/$U" \
      DISPLAY="$DISP" \
      XDG_RUNTIME_DIR="/run/user/$UID_M2" \
      WINEPREFIX="$PREFIX" \
      WINEARCH=win64 \
      WINEDEBUG="${WINEDEBUG:--all}" \
      WINEDLLOVERRIDES="mscoree,mshtml=;d3d8,d3d9,dxgi=n,b" \
      DXVK_HUD="${DXVK_HUD:-fps,gpu,devinfo}" \
      DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-info}" \
      DXVK_LOG_PATH='C:\Games\Metin2\dxvk-logs' \
      DXVK_STATE_CACHE_PATH='C:\Games\Metin2\dxvk-state' \
      sh -c 'cd "$HOME/metin2lab/wine/prefix/drive_c/Games/Metin2" && exec "$0" metin2client.exe' \
      "$WINE_BIN" 2>&1 | tee "$LOG"
launch_rc=${PIPESTATUS[0]}
set -e

echo
echo "== el cliente termino con codigo $launch_rc =="
echo "== log de DXVK (si existe, DXVK se cargo) =="
DXLOG_DIR="$GAME/dxvk-logs"
# Ojo: un glob como "$DXLOG_DIR"/*.log lo expande TU shell, que no puede
# atravesar /home/metin2 (0700); sudo llegaria tarde y el glob quedaria literal.
# Por eso se busca con find ya con sudo.
DXLOGS="$(sudo find "$DXLOG_DIR" -maxdepth 1 -type f -name '*_d3d*.log' -print 2>/dev/null || true)"
if [ -n "$DXLOGS" ]; then
  printf '%s\n' "$DXLOGS"
  mkdir -p "$HOME/metin2lab/logs"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if sudo cp -f "$f" "$HOME/metin2lab/logs/" 2>/dev/null; then
      sudo chown "$(id -u):$(id -g)" "$HOME/metin2lab/logs/$(basename "$f")" 2>/dev/null || true
    fi
  done <<< "$DXLOGS"
  echo "-- copiado a $HOME/metin2lab/logs/ (para publicarlo junto al log del cliente)"
else
  echo "(no hay log de DXVK en $DXLOG_DIR)"
  echo "Si arriba aparecen lineas 'info: DXVK: v...', DXVK si se cargo."
fi
echo "== cerrando wineserver del prefijo =="
sudo -u "$U" env HOME="/home/$U" WINEPREFIX="$PREFIX" WINEARCH=win64 \
  wineserver -k 2>/dev/null || true
echo "log guardado en: $LOG"
