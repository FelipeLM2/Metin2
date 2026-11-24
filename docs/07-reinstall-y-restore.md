# Reinstalación y restauración segura (CachyOS + Hyprland + DMS)

Guía paso a paso para **no perder nada** al reinstalar CachyOS desde cero.
Está escrita para seguirse con el móvil o en otra máquina mientras se hace.
No ejecuta nada por sí sola: son comandos para copiar y pegar **de uno en uno**.

Estado al escribirla (2026-11-23): el backup ya está completo y verificado.
Se arrancó una copia de `m2-server` desde el propio backup y llegó al `login:`
de FreeBSD. No vuelvas a correr `backup-hdd.sh`: recopiaría 43 G otra vez.

---

## Antes de empezar: dónde está cada cosa

| Disco | Contenido | Se toca durante la instalación |
|---|---|---|
| `/dev/sda` (SSD 500 G) | CachyOS actual, VMs originales | **SÍ**: es el que se formatea |
| `/dev/sdb3` (HDD 1 T, `Datos`) | Tus vídeos, muy importantes | **NO**. Desconectar físicamente |
| `/dev/sdc1` (SSD 128 G, `M2BACKUP`) | Copia cifrada `metin2-backup.img` | **NO**. Desconectar físicamente |

Dentro del contenedor cifrado (`/mnt/backup`) está la carpeta
`/mnt/backup/2026-11-23/` con el backup completo.

> Regla de oro: **`sda` se formatea sí o sí** al instalar CachyOS (es el disco
> del sistema). Lo que **no se toca** es `sdc` (el backup cifrado) y `sdb` (tus
> vídeos). Por eso es imprescindible tener el backup verificado **antes** de
> arrancar el instalador: cuando `sda` se borre, no habrá vuelta atrás en ese
> disco. No borres nada a mano en `sdc` ni en `sdb`.

---

## Paso 1 — Guardar la frase contraseña y el header LUKS (fuera del SSD)

El `luksHeaderBackup` **no sustituye** a la frase contraseña: sin la frase no
se puede abrir el contenedor aunque tengas el header. Necesitas **las dos
cosas**, en **sitios distintos** y **fuera del SSD de 128 G** (si el SSD muere,
no puedes guardar la copia en el SSD).

Tu sitio seguro es **tu carpeta personal de Google Drive**. Úsala, pero con una
regla: **la frase y el header no van juntos**. Si alguien entra en tu Drive y
ve los dos en la misma carpeta, tiene la caja y la llave. Sepáralos:

- **Header** → tu carpeta personal de Drive (la que quieres sí o sí).
- **Frase** → papel a mano y/o gestor de contraseñas / nota en **otra** carpeta
  o dispositivo (móvil). Nunca en la misma carpeta que el header.

Si al final solo guardas una cosa, **guarda la frase**: el contenedor original
conserva su header, así que con la frase basta para abrirlo.

### 1a. La frase contraseña

- Escríbela a mano en un papel y guárdala donde no se pierda.
- O guárdala en un gestor de contraseñas en otro dispositivo (móvil, otro PC).
- **No** la pongas en un `.txt` dentro de `M2BACKUP` ni en la misma carpeta de
  Drive que el header.

### 1b. Subir el header a tu carpeta de Drive

El header ya existe en `/mnt/backupdisk/metin2-luks-header.img` (dentro del
SSD de 128 G). Súbelo a Drive.

**Opción A — con `rclone` ya configurado:**

```bash
# Ajusta "drive" al nombre de tu remote y "MiCarpetaPersonal" a la real
rclone copy /mnt/backupdisk/metin2-luks-header.img drive:MiCarpetaPersonal/ --progress

# Verifica que llegó íntegro: los dos hashes deben coincidir
sha256sum /mnt/backupdisk/metin2-luks-header.img
rclone cat drive:MiCarpetaPersonal/metin2-luks-header.img | sha256sum
rclone ls drive:MiCarpetaPersonal/metin2-luks-header.img
```

**Opción B — sin `rclone` (la fácil):**

1. Abre Drive en el navegador.
2. Arrastra `/mnt/backupdisk/metin2-luks-header.img` a tu carpeta personal.
3. Desde el **móvil**, abre esa carpeta y confirma que el archivo está ahí y se
   puede descargar.

> No hace falta ningún `/dev/sdd1` ni `/mnt/externo`: el externo de 1 T ya no
> es obligatorio. Drive es tu copia fuera del SSD. Si más adelante conectas el
> externo, puedes copiar el header allí también como tercera copia.

### 1c. Comprobación de que la frase funciona

Sin abrir nada nuevo, prueba la frase contra el header original:

```bash
sudo cryptsetup luksOpen --test-passphrase /mnt/backupdisk/metin2-luks-header.img
```

Si acepta la frase, está bien. **No sigas hasta que esto funcione.** Después de
formatear, cuando hayas descargado el header de Drive, podrás probarlo con:

```bash
sudo cryptsetup luksOpen --test-passphrase /ruta/al/metin2-luks-header.img
```

---

## Paso 2 — Preparar el equipo antes de formatear

1. Cierra el juego y las VMs con normalidad:
   ```bash
   bash ~/metin2-docs/tools/c01/90-netns-down.sh
   ssh root@10.10.10.10 "cd /usr/metin2/server && sh close.sh"
   sudo virsh -c qemu:///system shutdown m2-server
   ```
2. Apaga también `metin2-vm` desde dentro del VM (apagado limpio, sin
   `virsh destroy`).
3. Comprueba que no queda nada escribiendo en el backup:
   ```bash
   df -h /mnt/backup
   sudo sync
   ```
4. **Desconecta físicamente** `sdb` (vídeos) y `sdc` (backup). Si es un
   portátil y no puedes, revisa el instalador dos veces: solo debe seleccionar
   `/dev/sda`.

---

## Paso 3 — Instalar CachyOS

- Arranca el instalador de CachyOS (USB).
- Elige **instalar en `/dev/sda`**, borrando solo ese disco.
- Usuario: puedes llamarte `deadivine` otra vez para que las rutas del backup
  encajen mejor. Si eliges otro nombre, habrá que ajustar rutas en el paso 5.
- **No marques** `sdb` ni `sdc`. Si aparecen, deben estar desconectados.
- Instala también `openssh`, `rsync` y `qemu/libvirt` si el instalador lo
  permite (o hazlo justo después con `pacman`).
- Termina la instalación y reinicia **sin los discos desconectados todavía**
  (sigue con solo `sda`).

---

## Paso 4 — Hyprland primero, DankMaterialShell después

- Arranca CachyOS y comprueba que(funciona el escritorio base.
- Instala Hyprland siguiendo la guía oficial de CachyOS. Arráncalo desde el
  display manager (o `Hyprland` desde tty) y comprueba que abre, que el teclado
  responde y que la GTX 1650 da salida.
- **Solo cuando Hyprland arranque bien**, instala DankMaterialShell y
  configúralo sobre Hyprland.
- Mantén Plasma instalado: si Hyprland/DMS falla, puedes volver a Plasma sin
  reinstalar.
- Tras esto, conecta de nuevo `sdc` (backup). **No conectes `sdb` aún.**

---

## Paso 5 — Abrir el backup en el sistema nuevo

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS        # confirma que el SSD es sdc1/M2BACKUP
sudo mkdir -p /mnt/backupdisk /mnt/backup
sudo mount /dev/sdc1 /mnt/backupdisk
sudo cryptsetup open /mnt/backupdisk/metin2-backup.img m2backup   # pide la frase del paso 1
sudo mount /dev/mapper/m2backup /mnt/backup
D=/mnt/backup/2026-11-23
ls -lh "$D"
cat "$D/MANIFEST.txt"
```

Antes de copiar nada, comprueba los hashes otra vez en el sistema nuevo:

```bash
LC_ALL=C sha256sum -c "$D/MANIFEST.sha256" 2>&1 | grep -vF ': OK' || echo "HASHES OK"
sudo qemu-img check -r all "$D/vm/metin2-vm.qcow2" 2>&1 | tail -5
```

Deben salir `HASHES OK` y `No errors were found on the image.`.

---

## Paso 6 — Restaurar todo (en este orden)

### 6.1 Paquetes base

```bash
sudo pacman -Syu
sudo pacman -S rsync qemu libvirt virt-manager openssh zstd
sudo systemctl enable --now libvirtd
```

### 6.2 Redes (primero, porque las VM las necesitan)

```bash
D=/mnt/backup/2026-11-23
sudo cp -av "$D/vm/networks-raw/"* /etc/libvirt/qemu/networks/
sudo virsh net-define /etc/libvirt/qemu/networks/default.xml
sudo virsh net-define /etc/libvirt/qemu/networks/metin2lab.xml
sudo virsh net-define /etc/libvirt/qemu/networks/red-lab.xml
sudo virsh net-start default
sudo virsh net-start metin2lab
sudo virsh net-start red-lab
sudo virsh net-autostart default metin2lab red-lab
virsh net-list --all
```

Deben aparecer `default`, `metin2lab` y `red-lab`. **No existe** `virbr-lab`
como red: es el puente que crea libvirt al arrancar la VM.

### 6.3 Servidor FreeBSD (`m2-server`)

```bash
sudo mkdir -p /var/lib/libvirt/images/m2-server
sudo rsync -aHAX --numeric-ids "$D/vm/m2-server/" /var/lib/libvirt/images/m2-server/
sudo chmod -R a+rX /var/lib/libvirt/images/m2-server
sudo virsh define "$D/vm/m2-server.xml"
sudo virsh start m2-server
virsh domstate m2-server
ssh root@10.10.10.10 hostname
```

Dentro de la FreeBSD:

```sh
cd /usr/metin2/server && sh start.sh
sockstat -4 -l | grep -E ':11000|:13001|:15000'
```

Deben salir los tres puertos. Si el SSH funciona y el juego arranca, la
restauración del servidor está verificada.

### 6.4 Usuario `metin2` y laboratorio

```bash
cat "$D/client/usuario-metin2.txt"          # uid, grupos y línea de passwd
sudo useradd -u 1001 -m -s /bin/bash -G render,video metin2
sudo chmod 700 /home/metin2
sudo rsync -aHAX --numeric-ids "$D/client/metin2lab/" /home/metin2/metin2lab/
sudo rsync -aHAX --numeric-ids "$D/client/metin2lab-golden/" /home/metin2/metin2lab-golden/
sudo chown -R metin2:metin2 /home/metin2
sudo cp -av "$D/client/netns/"* /etc/netns/
mkdir -p ~/.local/bin
cp -av "$D/client/Xephyr" ~/.local/bin/Xephyr
cp -av "$D/configs/local-bin/"* ~/.local/bin/
cp -av "$D/configs/repo/" ~/metin2-docs/
```

> Ajusta el `useradd` si `usuario-metin2.txt` dice otro uid/grupos. No borres
> `metin2lab-golden`.

### 6.5 Cliente Windows de respaldo y OpenCode (`metin2-vm`)

```bash
sudo cp -av "$D/vm/metin2-vm.qcow2" /var/lib/libvirt/images/metin2-vm.qcow2
sudo chmod a+r /var/lib/libvirt/images/metin2-vm.qcow2
sudo virsh define "$D/vm/metin2-vm.xml"
sudo virsh start metin2-vm
```

Arranca el VM, comprueba que Windows abre y que OpenCode tiene las sesiones.
Ahí está el historial de la conversación.

### 6.6 Repo y comprobación final

```bash
cd ~/metin2-docs
git status
git log -1 --oneline
bash tools/c01/35-check-isolation.sh    # si vuelves a jugar, con el servidor arriba
```

Checklist antes de darlo por terminado:

- [ ] `HASHES OK` y `No errors were found` en el paso 5.
- [ ] `ssh root@10.10.10.10 hostname` responde.
- [ ] `sockstat` muestra `11000`, `13001` y `15000`.
- [ ] `metin2-vm` arranca y OpenCode conserva las sesiones.
- [ ] `metin2lab` y `metin2lab-golden` existen en `/home/metin2`.
- [ ] Redes `default`, `metin2lab` y `red-lab` activas.

Solo con todo eso verde da por buena la restauración. Recuerda: `sda` ya se
formateó en el paso 3, así que aquí no hay originales viejos que borrar; lo que
queda es decidir si conservas o limpias el backup de `sdc` (y solo cuando tú
quieras).

---

## Si algo falla

- No borres nada en `sdc` ni en `sdb`. El backup sigue intacto en `sdc` y solo
  se formateó `sda` (paso 3), que es lo esperado.
- Para volver a montar: repetir el paso 5.
- Para probar un qcow2 sin arrancar el original, se puede hacer un overlay
  delgado (`qemu-img create -b ...`) como se hizo con `m2-server-test`.
- Si la frase no abre, descarga el header de Drive (paso 1b) y usa
  `sudo cryptsetup luksOpen --header /ruta/al/metin2-luks-header.img /mnt/backupdisk/metin2-backup.img m2backup`.
- Si Hyprland/DMS no arranca, entra en Plasma y sigue por terminal; la
  restauración no depende del escritorio.
