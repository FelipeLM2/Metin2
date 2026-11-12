#!/usr/bin/env bash
# C01-bis - Resolucion y modo de pantalla del cliente (metin2.cfg).
# Escribe SOLO en el prefijo de Wine del usuario metin2. No lanza el juego,
# no usa red y no toca preferencias del escritorio.
#
# Antes de cambiar nada guarda una copia: metin2.cfg.bak-AAAAMMDD-HHMMSS
# (se conservan las 5 ultimas). Para volver atras: restore.
#
# Uso (con el juego cerrado):
#   bash tools/c01bis/32-game-res.sh ver
#   bash tools/c01bis/32-game-res.sh fullscreen            # mantiene WxH
#   bash tools/c01bis/32-game-res.sh fullscreen 1280x720
#   bash tools/c01bis/32-game-res.sh ventana 1280x720
#   bash tools/c01bis/32-game-res.sh restore
#
# En pantalla completa (WINDOWED ausente) el cliente cambia el modo de video
# y la ventana cubre toda la pantalla; en ventana recorta W/H al tamano del
# display pero deja la barra de titulo.
set -euo pipefail

U=metin2
GAME="/home/$U/metin2lab/wine/prefix/drive_c/Games/Metin2"
CFG="$GAME/metin2.cfg"
ACTION="${1:-ver}"
ARG2="${2:-}"

die() { echo "ERROR: $*" >&2; exit 1; }

sudo -u "$U" test -d "$GAME" \
  || die "no existe $GAME (ejecuta antes tools/c01bis/10-usuario.sh)"
sudo -u "$U" test -f "$CFG" \
  || die "no existe $CFG: arranca el cliente una vez para que lo cree"

# Comprueba /proc/*/comm y no la linea de comandos: asi no confundimos el
# propio "sudo ... pgrep" con el juego.
game_running() {
  sudo -u "$U" sh -c 'for d in /proc/[0-9]*; do
      [ -r "$d/comm" ] || continue
      read -r c < "$d/comm" || continue
      case "$c" in metin2client*) exit 0 ;; esac
    done
    exit 1'
}

need_closed() {
  if game_running; then
    die "el cliente esta abierto. Cierralo (o bash tools/c01/90-netns-down.sh) y repite"
  fi
}

cfg_get() {
  sudo -u "$U" awk -v k="$1" '
    { if (toupper($1) == k) v = $2 }
    END { print v }' "$CFG"
}

cfg_geom() {
  local w h
  w="$(cfg_get WIDTH)"; h="$(cfg_get HEIGHT)"
  [ -n "$w" ] && [ -n "$h" ] || { echo "1280x720"; return; }
  echo "${w}x${h}"
}

print_cfg() {
  echo "== $CFG =="
  sudo -u "$U" awk '
    { k = toupper($1) }
    k == "WIDTH"     { printf "  %-10s %s\n", k, $2; hit[k] = 1 }
    k == "HEIGHT"    { printf "  %-10s %s\n", k, $2; hit[k] = 1 }
    k == "BPP"       { printf "  %-10s %s\n", k, $2; hit[k] = 1 }
    k == "FREQUENCY" { printf "  %-10s %s\n", k, $2; hit[k] = 1 }
    k == "WINDOWED"  { printf "  %-10s %s\n", k, $2; hit[k] = 1 }
    END {
      if (!hit["WINDOWED"]) printf "  %-10s (ausente = pantalla completa)\n", "WINDOWED"
    }' "$CFG"
  echo "  copias: $(sudo -u "$U" sh -c 'ls -1 "$1".bak-* 2>/dev/null | wc -l' _ "$CFG" | tr -d ' ')"
}

parse_geom() {
  local g="${1:-}"
  [ -n "$g" ] || g="$(cfg_geom)"
  if ! [[ "$g" =~ ^([0-9]{3,4})x([0-9]{3,4})$ ]]; then
    die "formato de resolucion: 1280x720 (recibido: '$g')"
  fi
  W="${BASH_REMATCH[1]}"
  H="${BASH_REMATCH[2]}"
  [ "$W" -ge 800 ] && [ "$H" -ge 600 ] || die "minimo 800x600"
}

# $1 = 1 para dejar WINDOWED 1; 0 para quitarlo (pantalla completa).
apply() {
  local win="$1"
  need_closed
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  sudo -u "$U" cp -p "$CFG" "$CFG.bak-$ts"
  # Poda: deja las 5 copias mas recientes.
  sudo -u "$U" sh -c \
    'ls -1t "$1".bak-* 2>/dev/null | tail -n +6 | while IFS= read -r f; do rm -f -- "$f"; done' \
    _ "$CFG"
  sudo -u "$U" bash -s -- "$CFG" "$W" "$H" "$win" <<'EOS'
set -euo pipefail
cfg=$1; w=$2; h=$3; win=$4
tmp="$cfg.tmp.$$"
awk -v W="$w" -v H="$h" -v WIN="$win" '
  function put(k, v) { printf "%-30s %s\n", k, v }
  BEGIN { seenW = seenH = seenB = seenN = 0 }
  {
    k = toupper($1)
    if (k == "WIDTH")    { put("WIDTH", W);    seenW = 1; next }
    if (k == "HEIGHT")   { put("HEIGHT", H);   seenH = 1; next }
    if (k == "BPP")      { put("BPP", 32);     seenB = 1; next }
    if (k == "WINDOWED") {
      if (WIN == "1") put("WINDOWED", 1)
      seenN = 1
      next
    }
    print
  }
  END {
    if (!seenW) put("WIDTH", W)
    if (!seenH) put("HEIGHT", H)
    if (!seenB) put("BPP", 32)
    if (!seenN && WIN == "1") put("WINDOWED", 1)
  }' "$cfg" > "$tmp"
mv -f -- "$tmp" "$cfg"
EOS
}

case "$ACTION" in
  ver)
    print_cfg
    echo
    echo "Modo: $( [ "$(cfg_get WINDOWED)" = "1" ] && echo 'ventana' || echo 'pantalla completa' )"
    ;;
  fullscreen)
    parse_geom "$ARG2"
    apply 0
    print_cfg
    echo
    echo "OK: pantalla completa ${W}x${H} (WINDOWED fuera del cfg)."
    echo "El cliente cambia el modo de video y la ventana cubre el display."
    ;;
  ventana)
    parse_geom "$ARG2"
    apply 1
    print_cfg
    echo
    echo "OK: ventana ${W}x${H} (WINDOWED 1)."
    echo "El cliente recorta W/H al tamano del display si no cabe."
    ;;
  restore)
    need_closed
    LAST="$(sudo -u "$U" sh -c 'ls -1t "$1".bak-* 2>/dev/null | head -n 1' _ "$CFG" || true)"
    [ -n "$LAST" ] || die "no hay copias $CFG.bak-*"
    sudo -u "$U" cp -p "$LAST" "$CFG"
    echo "restaurado desde: $LAST"
    print_cfg
    ;;
  -h|--help|help)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "accion desconocida: $ACTION (ver, fullscreen, ventana, restore)"
    ;;
esac
