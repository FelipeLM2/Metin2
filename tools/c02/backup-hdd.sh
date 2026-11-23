#!/usr/bin/env bash
# C02 — Copia completa del laboratorio al SSD cifrado (/mnt/backup).
#
# Uso:
#   tools/c02/backup-hdd.sh              Fase A: todo salvo el qcow2 de metin2-vm
#                                        (se puede correr con metin2-vm encendida)
#   tools/c02/backup-hdd.sh --vm-fria    Fase B: añade metin2-vm.qcow2 + copia
#                                        pequeña de OpenCode. Requiere VM apagada.
#
# Reglas: no borra nada, no usa --delete, no hace commit/push, no toca /dev/sdb
# (disco de los vídeos). El destino es el contenedor LUKS montado en /mnt/backup.

set -Eeuo pipefail
shopt -s nullglob

MODO="${1:-}"
DEST_ROOT="/mnt/backup"
DISK_MNT="/mnt/backupdisk"
MAPPER="/dev/mapper/m2backup"
FECHA="$(date +%F)"
DST="$DEST_ROOT/$FECHA"
MANIFEST="$DST/MANIFEST.txt"
USER_NAME="${USER:-deadivine}"
GROUP_NAME="$(id -gn)"

if (( EUID == 0 )); then SUDO=""; else SUDO="sudo"; fi

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'AVISO: %s\n' "$*" | tee -a "$MANIFEST" >&2; }
log()  { printf '%s\n' "$*" | tee -a "$MANIFEST"; }
cmd()  { log "\$ $*"; }

# ---------------------------------------------------------------------------
# Preflight (no escribimos nada hasta aquí)
# ---------------------------------------------------------------------------
for c in rsync virsh qemu-img tar zstd sha256sum du findmnt getent; do
  command -v "$c" >/dev/null || die "falta el comando $c"
done

case "$MODO" in
  ""|--vm-fria) ;;
  *) die "uso: $0 [--vm-fria]" ;;
esac

SRC_QCOW="$(findmnt -no SOURCE "$DEST_ROOT" 2>/dev/null || true)"
[[ "$SRC_QCOW" == "$MAPPER" ]] || die "/mnt/backup no está en $MAPPER (está en '$SRC_QCOW')"
[[ -d "$DISK_MNT" ]] || die "no existe $DISK_MNT (donde vive el .img cifrado)"

if [[ "$MODO" == "--vm-fria" ]]; then
  [[ -d "$DST" ]] || die "no existe $DST; ejecuta primero sin opciones"
else
  [[ ! -e "$DST" ]] || die "ya existe $DST; no sobrescribo. Renómbralo o bórralo a mano."
fi

# ---------------------------------------------------------------------------
# Funciones
# ---------------------------------------------------------------------------
copiar_metadatos() {
  log "== Metadatos libvirt =="
  cmd "virsh dumpxml ..."
  for d in m2-server metin2-vm Metin2-Client win10; do
    $SUDO virsh dumpxml "$d" > "$DST/vm/$d.xml" 2>/dev/null || warn "no se pudo dumpxml $d"
  done
  for n in virbr-lab default; do
    $SUDO virsh net-dumpxml "$n" > "$DST/vm/$n.xml" 2>/dev/null || true
  done
  $SUDO virsh net-list --all > "$DST/vm/net-list.txt" 2>/dev/null || true
  $SUDO virsh snapshot-list m2-server > "$DST/vm/snapshots/m2-server-list.txt" 2>/dev/null || true
  $SUDO virsh domblklist m2-server > "$DST/vm/m2-server-domblklist.txt" 2>/dev/null || true
  $SUDO virsh domblklist metin2-vm > "$DST/vm/metin2-vm-domblklist.txt" 2>/dev/null || true
  if [[ -d /var/lib/libvirt/qemu/snapshot/m2-server ]]; then
    cmd "cp -a /var/lib/libvirt/qemu/snapshot/m2-server/. -> vm/snapshots/"
    $SUDO cp -a /var/lib/libvirt/qemu/snapshot/m2-server/. "$DST/vm/snapshots/"
  fi
}

copiar_servidor() {
  log "== Cadena qcow2 de m2-server (VM apagada) =="
  local src=/var/lib/libvirt/images/m2-server
  [[ -d "$src" ]] || die "no existe $src"
  cmd "rsync $src/ -> $DST/vm/m2-server/"
  $SUDO rsync -aHAX --numeric-ids --info=progress2 "$src/" "$DST/vm/m2-server/"

  log "-- qemu-img check de cada capa --"
  : > "$DST/logs/qemu-img-check.txt"
  local img
  for img in "$DST"/vm/m2-server/*; do
    [[ -f "$img" ]] || continue
    if $SUDO qemu-img info "$img" 2>/dev/null | grep -q 'file format: qcow2'; then
      printf '== %s ==\n' "$(basename "$img")" >> "$DST/logs/qemu-img-check.txt"
      $SUDO qemu-img check "$img" >> "$DST/logs/qemu-img-check.txt" 2>&1 \
        || warn "qemu-img check falló: $(basename "$img")"
    fi
  done

  # /usr/metin2 y /var/db/mysql viven dentro del qcow2. Si hay libguestfs,
  # los extraemos también como tar.zst para restauración rápida.
  local top="$DST/vm/m2-server/metin2-server.Credenciales-ok"
  if command -v virt-copy-out >/dev/null; then
    cmd "virt-copy-out /usr/metin2 /var/db/mysql -> server/"
    if $SUDO virt-copy-out -a "$top" /usr/metin2 /var/db/mysql "$DST/server/" \
         >> "$DST/logs/virt-copy-out.txt" 2>&1; then
      tar -C "$DST/server" -cf - metin2 mysql 2>/dev/null \
        | zstd -T0 -q > "$DST/server/server-data.tar.zst" \
        || warn "no se pudo comprimir server-data.tar.zst"
      zstd -t "$DST/server/server-data.tar.zst" 2>/dev/null \
        || warn "zstd -t falló en server-data.tar.zst"
    else
      warn "virt-copy-out falló: /usr/metin2 y la DB siguen dentro del qcow2"
    fi
  else
    warn "no hay virt-copy-out: /usr/metin2 y la DB siguen dentro del qcow2"
  fi

  cat > "$DST/sql/README.txt" <<'EOF'
El dump lógico de MariaDB NO se generó automáticamente: m2-server estaba
apagado para que la copia del qcow2 sea coherente. La base de datos completa
está dentro de vm/m2-server/ (en /var/db/mysql) y también, si estaba disponible
virt-copy-out, en server/server-data.tar.zst.

Para añadir un dump SQL legible más adelante:
  1. Arranca m2-server con su configuración normal.
  2. Para el juego dentro de FreeBSD.
  3. mysqldump -u root -p --all-databases | zstd -T0 -q > metin2.sql.zst
  4. Copia ese archivo a esta misma carpeta sql/ del backup.
  5. Verifica con: zstd -t sql/metin2.sql.zst
Este README y su contenido NO van al repo de GitHub.
EOF
}

copiar_cliente() {
  log "== Cliente Wine, Xephyr, jaulas y configuración =="
  local l=/home/metin2
  cmd "rsync $l/metin2lab/ -> client/metin2lab/"
  $SUDO rsync -aHAX --numeric-ids --info=progress2 "$l/metin2lab/" "$DST/client/metin2lab/"
  cmd "rsync $l/metin2lab-golden/ -> client/metin2lab-golden/"
  $SUDO rsync -aHAX --numeric-ids --info=progress2 "$l/metin2lab-golden/" "$DST/client/metin2lab-golden/"

  if [[ -x "$HOME/.local/bin/Xephyr" ]]; then
    cmd "cp ~/.local/bin/Xephyr -> client/Xephyr"
    cp -a "$HOME/.local/bin/Xephyr" "$DST/client/Xephyr"
  else
    warn "no existe ~/.local/bin/Xephyr (Xephyr parcheado); se usará el de pacman al restaurar"
  fi

  cmd "rsync /etc/netns/ -> client/netns/"
  $SUDO rsync -aHAX --numeric-ids /etc/netns/ "$DST/client/netns/" 2>/dev/null \
    || warn "no se pudo copiar /etc/netns/"

  getent passwd metin2 > "$DST/client/usuario-metin2.txt" 2>/dev/null || true
  id metin2 >> "$DST/client/usuario-metin2.txt" 2>/dev/null || true

  cmd "rsync ~/.local/bin/ -> configs/local-bin/"
  rsync -aHAX --numeric-ids "$HOME/.local/bin/" "$DST/configs/local-bin/" 2>/dev/null || true
  cmd "rsync ~/.config/ -> configs/dot-config/ (sin cachés)"
  rsync -aHAX --numeric-ids \
    --exclude='*/Cache' --exclude='*/Code Cache' --exclude='*/CachedData' \
    --exclude='*/GPUCache' --exclude='*/Service Worker' \
    "$HOME/.config/" "$DST/configs/dot-config/" 2>/dev/null || true

  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  cmd "rsync $repo_root/ -> configs/repo/ (docs + scripts propios)"
  rsync -aHAX --numeric-ids "$repo_root/" "$DST/configs/repo/"
}

copiar_vm_fria() {
  log "== Fase B: metin2-vm (OpenCode) =="
  local state img=/var/lib/libvirt/images/metin2-vm.qcow2
  state="$($SUDO virsh domstate metin2-vm 2>/dev/null || true)"
  if [[ "$state" != *apagado* && "$state" != *"shut off"* && "$state" != *"shut down"* ]]; then
    die "metin2-vm está en estado '$state'. Apágala limpiamente y vuelve a correr con --vm-fria"
  fi
  [[ -f "$img" ]] || die "no existe $img"
  cmd "rsync $img -> vm/metin2-vm.qcow2"
  $SUDO rsync -aHAX --numeric-ids --info=progress2 "$img" "$DST/vm/"
  $SUDO qemu-img check "$DST/vm/metin2-vm.qcow2" >> "$DST/logs/qemu-img-check.txt" 2>&1 \
    || warn "qemu-img check falló en metin2-vm.qcow2"

  # Copia pequeña y separada de la DB de OpenCode por si el qcow2 se estropea.
  if command -v virt-copy-out >/dev/null; then
    cmd "virt-copy-out OpenCode -> opencode/"
    $SUDO virt-copy-out -a "$img" \
      /Users/Metin2/.local/share/opencode /Users/Metin2/.config/opencode \
      "$DST/opencode/" >> "$DST/logs/virt-copy-out.txt" 2>&1 \
      || warn "virt-copy-out de OpenCode falló (la DB sigue dentro del qcow2)"
  else
    warn "no hay virt-copy-out: la DB de OpenCode sigue dentro del qcow2"
  fi
}

finalizar() {
  log "== Verificación final =="
  local z
  for z in "$DST"/*.zst "$DST"/server/*.zst "$DST"/sql/*.zst; do
    [[ -f "$z" ]] || continue
    zstd -t "$z" 2>/dev/null || warn "zstd -t falló: $(basename "$z")"
  done
  find "$DST" -type f ! -name 'MANIFEST*' -size -10M -print0 2>/dev/null \
    | sort -z | xargs -0 -r sha256sum > "$DST/MANIFEST.sha256" || true
  du -sh "$DST"/* 2>/dev/null | sort -h >> "$MANIFEST" || true
  $SUDO chown -R "$USER_NAME:$GROUP_NAME" "$DST"

  if [[ "$MODO" != "--vm-fria" ]]; then
    log ""
    log "PENDIENTE: apaga limpiamente metin2-vm y ejecuta:"
    log "  tools/c02/backup-hdd.sh --vm-fria"
    log "Después, verifica y solo entonces formatea /dev/sda. NO borres originales."
  else
    log ""
    log "COPIA TERMINADA. Antes de formatear: revisa logs/qemu-img-check.txt,"
    log "MANIFEST.sha256 y prueba una restauración con otro nombre/IP."
  fi
}

# ---------------------------------------------------------------------------
# Ejecución
# ---------------------------------------------------------------------------
if [[ "$MODO" == "--vm-fria" ]]; then
  copiar_vm_fria
  finalizar
  exit 0
fi

$SUDO mkdir -p "$DST"/{vm/m2-server,vm/snapshots,server,sql,client/netns,configs,opencode,logs}
$SUDO chown -R "$USER_NAME:$GROUP_NAME" "$DST"

{
  printf 'BACKUP DEL LABORATORIO METIN2 — %s\n' "$FECHA"
  printf 'Modo: %s\n' "${MODO:-fase A}"
  printf 'Destino: %s (%s)\n' "$DST" "$MAPPER"
  printf 'Origen disco cifrado: %s\n' "$DISK_MNT"
  printf 'Orden: metadata -> m2-server -> cliente/Xephyr -> configs -> [fase B: metin2-vm]\n'
  printf 'Reglas: sin --delete, sin borrados, sin commit/push, sin tocar /dev/sdb.\n'
  printf '\n'
} > "$MANIFEST"

copiar_metadatos
copiar_servidor
copiar_cliente
finalizar
