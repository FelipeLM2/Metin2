#!/usr/bin/env bash
# C01-bis - Compila un Xephyr parcheado que reenvia el warp del puntero al
# servidor X real. Es lo que arregla la camara del juego (clic derecho) sin
# salir del display anidado.
#
# No toca paquetes ni ficheros del sistema: descarga el tarball oficial de la
# version de xorg-server instalada, aplica 14-xephyr-warp.patch y deja el
# binario en ~/.local/bin/Xephyr. Para volver al Xephyr de pacman, borra ese
# fichero (15-xephyr.sh usara el del sistema).
#
# Uso:
#   bash tools/c01bis/14-xephyr-warp.sh          # compila si falta
#   FORCE=1 bash tools/c01bis/14-xephyr-warp.sh  # recompila siempre
#   KEEP=1 bash tools/c01bis/14-xephyr-warp.sh   # conserva fuentes/build
#   VER=21.1.26 bash tools/c01bis/14-xephyr-warp.sh  # fuerza version
#
# Dependencias (Arch): base-devel meson ninja
#   sudo pacman -S --needed base-devel meson ninja
# Necesita unos minutos y ~300 MB libres en ~/.cache.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$HERE/14-xephyr-warp.patch"
DEST="${XEPHYR_DEST:-$HOME/.local/bin/Xephyr}"
BUILD_ROOT="${BUILD_ROOT:-$HOME/.cache/c01bis-xephyr}"
BASE_URL="https://xorg.freedesktop.org/releases/individual/xserver"
FORCE="${FORCE:-0}"
KEEP="${KEEP:-0}"
VER="${VER:-}"

die() { echo "ERROR: $*" >&2; exit 1; }
note() { echo "== $*"; }

[ "$(id -u)" -ne 0 ] || die "no lo ejecutes con sudo: el binario debe quedar en tu ~/.local/bin"
[ -f "$PATCH_FILE" ] || die "falta $PATCH_FILE"
command -v pacman >/dev/null 2>&1 || die "este script asume Arch/CachyOS (pacman)"
command -v curl   >/dev/null 2>&1 || die "falta curl (sudo pacman -S curl)"
command -v tar    >/dev/null 2>&1 || die "falta tar"
command -v patch  >/dev/null 2>&1 || die "falta patch (sudo pacman -S base-devel)"
command -v meson  >/dev/null 2>&1 || die "falta meson (sudo pacman -S meson)"
command -v ninja  >/dev/null 2>&1 || die "falta ninja (sudo pacman -S ninja)"

if [ -z "$VER" ]; then
  VER="$(pacman -Q xorg-server 2>/dev/null | awk '{print $2}')"
  [ -n "$VER" ] || die "no puedo leer la version de xorg-server (pacman -Q xorg-server)"
  VER="${VER%%-*}"
fi
case "$VER" in
  21.1.*) ;;
  *) die "version $VER no soportada: el parche es para xorg-server 21.1.x" ;;
esac

if [ "$FORCE" != "1" ] && [ -x "$DEST" ]; then
  echo "Ya existe $DEST:"
  "$DEST" -version 2>&1 | sed 's/^/  /' || true
  echo
  echo "Si quieres recompilar: FORCE=1 bash $0"
  echo "Si quieres volver al de pacman: rm -f $DEST"
  exit 0
fi

TARBALL="xorg-server-$VER.tar.xz"
URL="$BASE_URL/$TARBALL"
mkdir -p "$BUILD_ROOT" "$(dirname "$DEST")"
cd "$BUILD_ROOT"

if [ ! -f "$TARBALL" ]; then
  note "descargando $URL"
  curl -fL --retry 3 --retry-delay 2 -o "$TARBALL.part" "$URL" \
    || die "no pude descargar el tarball. Comprueba la version: pacman -Q xorg-server"
  mv -f "$TARBALL.part" "$TARBALL"
else
  note "uso el tarball ya descargado: $BUILD_ROOT/$TARBALL"
fi

# El proyecto publica .sig (GPG), no .sha256. Verificarlo obligaria a importar
# la clave de X.Org; en su lugar comprobamos que el tar trae el arbol esperado.
tar -tf "$TARBALL" | grep -qx "xorg-server-$VER/hw/kdrive/ephyr/hostx.c" \
  || die "$TARBALL no parece el tarball oficial de xorg-server $VER"

note "extrayendo $TARBALL"
rm -rf "src-$VER"
mkdir "src-$VER"
tar -xf "$TARBALL" -C "src-$VER" --strip-components=1
cd "src-$VER"

note "comprobando el parche (dry-run)"
patch -p1 --dry-run <"$PATCH_FILE" || die "el parche no aplica sobre $TARBALL"
patch -p1 <"$PATCH_FILE"
grep -q 'hostx_warp_pointer' hw/kdrive/ephyr/hostx.c \
  || die "tras parchear no aparece hostx_warp_pointer en hostx.c"

note "configurando (solo Xephyr, sin xorg/xnest/xvfb)"
meson setup build \
  --buildtype=release \
  -Dxorg=false \
  -Dxnest=false \
  -Dxvfb=false \
  -Dxephyr=true \
  -Dudev=false \
  -Dsystemd_logind=false

note "compilando Xephyr"
ninja -C build Xephyr

[ -x build/hw/kdrive/ephyr/Xephyr ] || die "no se genero build/hw/kdrive/ephyr/Xephyr"

note "instalando en $DEST"
install -Dm755 build/hw/kdrive/ephyr/Xephyr "$DEST"

note "verificando"
"$DEST" -version 2>&1 | sed 's/^/  /' || die "$DEST no arranca con -version"
if command -v nm >/dev/null 2>&1; then
  if nm "$DEST" 2>/dev/null | grep -qw hostx_warp_pointer; then
    echo "  simbolo hostx_warp_pointer: presente"
  else
    echo "AVISO: no veo el simbolo hostx_warp_pointer; puede que el parche no este." >&2
  fi
fi

if [ "$KEEP" != "1" ]; then
  note "limpiando fuentes y build (KEEP=1 para conservarlos)"
  find "$BUILD_ROOT" -mindepth 1 -maxdepth 1 ! -name "$TARBALL" \
    -exec rm -rf -- {} +
fi

cat <<EOF

OK: Xephyr parcheado instalado en:
  $DEST
15-xephyr.sh lo usara automaticamente si existe.

Prueba:
  bash tools/c01bis/16-xephyr-stop.sh
  HOST_GRAB=1 GEOM=1280x720 bash tools/c01bis/15-xephyr.sh
  bash tools/c01bis/30-run-client.sh
y arrastra con el boton derecho dentro del juego.

Si algo va mal, el Xephyr de pacman sigue intacto:
  rm -f "$DEST"
EOF
