#!/usr/bin/env bash
# C01 - Diagnostico de solo lectura. No cambia nada del sistema.
# Uso: bash tools/c01/00-diagnostico.sh
set -uo pipefail

sec() { printf '\n== %s ==\n' "$*"; }
SRC="$HOME/metin2lab/tmp4/Client/Client"
PACK="$HOME/metin2lab/work/b04"

sec "sistema"
uname -srm
grep -E '^(NAME|VERSION)=' /etc/os-release 2>/dev/null || true
printf 'usuario: %s (uid %s)\n' "${USER:-?}" "$(id -u)"

sec "sesion grafica"
printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-}"
printf 'DISPLAY=%s\n' "${DISPLAY:-}"
printf 'WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:-}"
printf 'XAUTHORITY=%s\n' "${XAUTHORITY:-}"
printf 'XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-}"

sec "GPU"
lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || echo "lspci no disponible"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null \
  || echo "nvidia-smi no disponible (driver libre o sin NVIDIA)"

sec "vulkan 64 bits"
if command -v vulkaninfo >/dev/null 2>&1; then
  vulkaninfo --summary 2>/dev/null | sed -n '1,90p'
else
  echo "falta vulkan-tools: sudo pacman -S vulkan-tools"
fi

sec "vulkan 32 bits (lo necesita DXVK para un .exe de 32 bits)"
ls -l /usr/lib32/libvulkan.so* 2>/dev/null || echo "NO veo /usr/lib32/libvulkan.so* (falta lib32-vulkan-icd-loader)"
ls -l /usr/lib32/libGLX_nvidia.so* /usr/lib32/libnvidia-glcore.so* 2>/dev/null \
  || echo "NO veo las libs NVIDIA de 32 bits (posible falta lib32-nvidia-utils)"

sec "wine"
if command -v wine >/dev/null 2>&1; then
  wine --version
else
  echo "wine NO instalado: sudo pacman -S wine"
fi
if command -v winetricks >/dev/null 2>&1; then
  printf 'winetricks: %s\n' "$(winetricks --version 2>/dev/null | head -n1)"
else
  echo "winetricks no instalado (opcional, solo si falta alguna DLL)"
fi

sec "espacio en disco"
df -h "$HOME"

sec "cliente TMP4 (origen)"
if [ -d "$SRC" ]; then
  echo "origen: $SRC"
  find "$SRC" -maxdepth 1 -mindepth 1 -printf '%y %10s %f\n' | sort -k3
  echo
  echo "ejecutables .exe en la raiz:"
  find "$SRC" -maxdepth 1 -type f -iname '*.exe' -printf '  %f (%s bytes)\n'
  echo
  echo "d3d9.dll / dxgi.dll locales (si hay, hay que revisarlos):"
  find "$SRC" -maxdepth 2 -type f \( -iname 'd3d9.dll' -o -iname 'dxgi.dll' \) -printf '  %p\n'
  echo "(vacio = bien, usaremos el DXVK del prefijo)"
else
  echo "NO existe $SRC"
fi

sec "posible anti-cheat"
if [ -d "$SRC" ]; then
  find "$SRC" -maxdepth 3 -type f \
    \( -iname '*hackshield*' -o -iname '*xigncode*' -o -iname '*xhunter*' \
       -o -iname '*nprotect*' -o -iname '*gameguard*' -o -iname '*anticheat*' \) \
    -printf '  %p\n' | head -n 40
  echo "(vacio = no se ve anti-cheat por nombre)"
else
  echo "sin cliente, no se comprueba"
fi

sec "pack parcheado (debe ser 17292 / 520704)"
for f in "$PACK/root.eix" "$PACK/root.epk"; do
  if [ -f "$f" ]; then stat -c '%s %n' "$f"; else echo "FALTA $f"; fi
done
sha256sum "$PACK/root.eix" "$PACK/root.epk" 2>/dev/null || true

sec "puente del laboratorio"
if ip link show virbr-lab >/dev/null 2>&1; then
  ip -brief addr show virbr-lab
else
  echo "NO existe virbr-lab: arranca la VM FreeBSD antes de seguir"
fi

sec "servidor FreeBSD"
if command -v ssh >/dev/null 2>&1; then
  ssh -o BatchMode=yes -o ConnectTimeout=4 root@10.10.10.10 'hostname; ifconfig em0' 2>&1 \
    | sed -n '1,4p' || echo "no se pudo entrar por SSH (¿VM encendida?)"
else
  echo "no hay ssh"
fi

printf '\n== fin ==\n'
