#!/usr/bin/env bash
# C01-bis - Crea el usuario Linux metin2 y mueve el laboratorio a su home.
# Se ejecuta una sola vez, como tu usuario (pide sudo).
# Uso: bash tools/c01bis/10-usuario.sh
set -euo pipefail

U=metin2
SRC="$HOME/metin2lab"
DST="/home/$U/metin2lab"

if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: ejecuta este script como tu usuario normal, no como root."
  echo "El script pide sudo cuando lo necesita; como root usaria /root como home."
  exit 1
fi

# Mover el prefijo con el juego abierto lo rompe. La jaula debe estar cerrada.
if ip netns list | awk '{print $1}' | grep -qx metin2lab; then
  echo "ERROR: la jaula metin2lab sigue abierta."
  echo "Ejecuta primero: bash tools/c01/90-netns-down.sh"
  exit 1
fi
if pgrep -f 'metin2client.exe' >/dev/null 2>&1; then
  echo "ERROR: hay un metin2client.exe en marcha. Cierralo antes de mover el laboratorio."
  exit 1
fi

echo "== usuario $U =="
if id "$U" >/dev/null 2>&1; then
  echo "ya existe (uid $(id -u "$U"))"
else
  sudo useradd -m -s /bin/bash "$U"
  echo "creado (uid $(id -u "$U"))"
fi

# GPU: el driver de NVIDIA suele exponer /dev/nvidia* como 0666, pero si
# existen los grupos render/video los añadimos para no depender de eso. Nunca
# audio: el cliente va en silencio a proposito.
for g in render video; do
  if getent group "$g" >/dev/null 2>&1; then
    sudo usermod -aG "$g" "$U"
  fi
done

# Sin sudo y sin grupos de escritorio: solo su home y los de GPU.
echo
echo "== grupos y sudo =="
id "$U"
sudo -l -U "$U" 2>&1 | head -n 5 || true

echo
echo "== protegiendo el home del usuario real =="
chmod 700 "$HOME"
stat -c '%A %U %n' "$HOME"

echo
if [ -d "$DST" ]; then
  if [ -d "$SRC" ]; then
    echo "ERROR: existen $SRC y $DST. No se cual usar; no toco nada."
    echo "Revisa los dos y decide cual conservar antes de repetir."
    exit 1
  fi
  echo "== $DST ya existe, no se mueve =="
else
  [ -d "$SRC" ] || { echo "ERROR: no existe $SRC"; exit 1; }
  echo "== moviendo $SRC -> $DST =="
  sudo mv "$SRC" "$DST"
fi

sudo chown -R "$U:$U" "$DST"
sudo chmod 700 "/home/$U"

echo
echo "== XDG_RUNTIME_DIR de $U =="
sudo install -d -m 700 -o "$U" -g "$U" "/run/user/$(id -u "$U")"

echo
echo "== comprobando el cliente en su nuevo sitio =="
sudo -u "$U" env HOME="/home/$U" sh -c \
  'ls -l "$HOME/metin2lab/wine/prefix/drive_c/Games/Metin2/metin2client.exe"'

echo
echo "OK. Siguiente: bash tools/c01bis/15-xephyr.sh"
