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

# Los discos de las VMs NUNCA van dentro del laboratorio del cliente: metin2
# ejecuta un .exe sin auditar y no debe poder renombrar ni sustituir la imagen
# del servidor. Ademas libvirt corre como libvirt-qemu y no puede depender de
# los permisos de /home/metin2. Si aparecen, se para antes de mover nada.
echo "== comprobando que no hay discos de VM en $SRC =="
VM_QC="$(sudo find "$SRC" -maxdepth 4 -type f -name '*.qcow2' -print 2>/dev/null | head -n 20 || true)"
if [ -d "$SRC/vm" ] || [ -n "$VM_QC" ]; then
  echo "ERROR: hay discos de VM dentro de $SRC."
  if [ -d "$SRC/vm" ]; then
    sudo find "$SRC/vm" -maxdepth 1 -type f -printf '  %p\n' 2>/dev/null || true
  fi
  if [ -n "$VM_QC" ]; then
    printf '%s\n' "$VM_QC" | sed 's/^/  /'
  fi
  echo "Los discos viven en /var/lib/libvirt/images (ver docs/02-entorno.md)."
  echo "Muevelos alli y repite; este script no mueve VMs."
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
echo "== comprobando que ninguna VM de libvirt use $HOME =="
if command -v virsh >/dev/null 2>&1; then
  DOMS="$(sudo virsh -c qemu:///system list --all --name 2>/dev/null || true)"
  HOMEREFS=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if sudo virsh -c qemu:///system dumpxml "$d" 2>/dev/null | grep -qF "$HOME/"; then
      HOMEREFS+="  - $d"$'\n'
    fi
  done <<< "$DOMS"
  if [ -n "$HOMEREFS" ]; then
    echo "ERROR: estas VMs de libvirt usan archivos de $HOME:"
    printf '%s' "$HOMEREFS"
    echo "Mueve esos discos a /var/lib/libvirt/images antes de cerrar el home."
    exit 1
  fi
  echo "ninguna VM usa $HOME"
else
  echo "(virsh no esta instalado; no hay VMs que comprobar)"
fi

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
