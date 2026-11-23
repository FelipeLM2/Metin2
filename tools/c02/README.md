# C02 — Copia completa al SSD cifrado

`backup-hdd.sh` guarda **todo** el laboratorio dentro del contenedor LUKS
montado en `/mnt/backup` (archivo `.img` en `/mnt/backupdisk`, que es el SSD
de 128 G). **No formatea nada, no borra nada, no hace commit ni push.**
El disco de los vídeos (`/dev/sdb3`, etiqueta `Datos`) nunca se toca.

## Preparación previa (ya hecha)

```bash
# SSD limpio, una sola partición ext4 etiquetada M2BACKUP en /mnt/backupdisk
sudo truncate -s 100G /mnt/backupdisk/metin2-backup.img
sudo cryptsetup luksFormat /mnt/backupdisk/metin2-backup.img
sudo cryptsetup luksHeaderBackup /mnt/backupdisk/metin2-backup.img \
  --header-backup-file /mnt/backupdisk/metin2-luks-header.img
sudo cryptsetup open /mnt/backupdisk/metin2-backup.img m2backup
sudo mkfs.ext4 -m 0 /dev/mapper/m2backup
sudo mkdir -p /mnt/backup && sudo mount /dev/mapper/m2backup /mnt/backup
```

La frase contraseña la elegiste tú; el header backup no la sustituye.

## Uso en dos fases

```bash
# Fase A — se puede correr AHORA, con metin2-vm todavía encendida
tools/c02/backup-hdd.sh

# ... termina la conversación, apaga metin2-vm limpiamente desde el VM ...

# Fase B — añade el qcow2 de 28 G y la copia pequeña de OpenCode
tools/c02/backup-hdd.sh --vm-fria
```

Ambas fases usan la misma carpeta fechada `/mnt/backup/AAAA-MM-DD/`. La fase B
se niega a correr si `metin2-vm` no está apagada; nunca usa `virsh destroy`.

## Qué se copia

| Ruta de destino | Contenido |
|---|---|
| `vm/m2-server/` | Cadena completa de 7 qcow2 + base de 7,37 G (snapshot `Credenciales-ok`), 8,6 G |
| `vm/snapshots/` | XML de los snapshots y `snapshot-list` |
| `vm/*.xml` | `dumpxml` de los 4 dominios + `net-list --all` |
| `vm/networks/`, `vm/networks-raw/` | `net-dumpxml` de **todas** las redes (`default`, `metin2lab`, `red-lab`) y copia literal de `/etc/libvirt/qemu/networks/` |
| `server/server-data.tar.zst` | `/usr/metin2` + `/var/db/mysql` extraídos del qcow2 (si hay `virt-copy-out`) |
| `sql/README.txt` | Instrucciones para añadir un `mysqldump` lógico después |
| `client/metin2lab/` | Cliente Wine (19 G) |
| `client/metin2lab-golden/` | Copia dorada (19 G), **no se borra** |
| `client/Xephyr` | Binario parcheado `~/.local/bin/Xephyr` (cámara aparcada) |
| `client/netns/` | `/etc/netns/metin2lab` y `/etc/netns/m2xephyr` |
| `client/usuario-metin2.txt` | `getent passwd metin2` + `id metin2` para recrear el usuario |
| `configs/local-bin/` | `~/.local/bin/` (incluye Xephyr y helpers) |
| `configs/dot-config/` | `~/.config/` sin cachés |
| `configs/repo/` | Repo local completo (docs + scripts propios; sin assets ni credenciales) |
| `opencode/` | Copia pequeña de la DB/config de OpenCode del VM (fase B, si hay `virt-copy-out`) |
| `logs/`, `MANIFEST.txt`, `MANIFEST.sha256` | Comandos, tamaños, `qemu-img check`, hashes |

**No se copia** `Metin2-Client` ni `win10` (sus XML sí, por si algún día cambias
de idea). No se copia `virtio-win-*.iso` (se vuelve a descargar).

## Verificación antes de formatear

```bash
cat /mnt/backup/$(date +%F)/MANIFEST.txt
grep -i error /mnt/backup/$(date +%F)/logs/qemu-img-check.txt || echo "qcow2 OK"
zstd -t /mnt/backup/$(date +%F)/server/server-data.tar.zst
LC_ALL=C sha256sum -c /mnt/backup/$(date +%F)/MANIFEST.sha256 2>&1 | grep -vF ': OK' || echo "HASHES OK"
```

Y, si puedes, arranca una copia de prueba de `m2-server` desde el SSD con otro
nombre e IP distinta. **No formatees `/dev/sda` hasta que eso funcione.**
No borres los originales hasta haber restaurado y verificado.

## Restauración (resumen)

1. Monta el contenedor: `cryptsetup open ... m2backup` + `mount`.
2. Copia `vm/m2-server/` a `/var/lib/libvirt/images/m2-server/` y los XML con
   `virsh define`. Define las redes desde `vm/networks-raw/` (`default`,
   `metin2lab` y `red-lab`); no hay ninguna red llamada `virbr-lab`.
3. Recrea el usuario `metin2` con `client/usuario-metin2.txt`, coloca
   `metin2lab` y `metin2lab-golden` en `/home/metin2`, y `/etc/netns/`.
4. Coloca `client/Xephyr` en `~/.local/bin/Xephyr` y el repo en su ruta.
5. Arranca `m2-server`, comprueba login y DB. Solo entonces da por buena la copia.

Nada de esto se ejecuta automáticamente: el script solo copia y verifica.
