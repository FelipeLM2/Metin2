# C01-bis — Usuario dedicado y X anidado

**Fecha:** 2026-11-09
**Máquina:** CachyOS (torre) y la VM FreeBSD (servidor).
**Riesgo:** bajo. No se instala nada del juego ni se descarga nada del pack. El
cliente es el mismo `.exe` de C01, con el mismo prefijo: solo cambia **con qué
usuario y en qué display corre**.

## Por qué este paso

C01b cerró lo importante: HUD de DXVK con la GTX 1650, conexiones solo a
`10.10.10.10`, sin salida a Internet y sin DNS. Pero el cliente seguía corriendo
como `deadivine`, con acceso a:

- su `/home` (documentos, claves SSH, historial),
- su display X (`:0`, puede inyectar teclado o leer el portapapeles),
- su bus de sesión y su audio.

C01-bis lo encierra en un usuario Linux aparte, `metin2`, y le da un display
anidado (Xephyr) que **solo muestra sus propias ventanas**. No ve el escritorio
real. Además, Xephyr corre dentro de un netns vacío (`m2xephyr`, solo `lo`):
si lo comprometen, no tiene red.

## Qué NO resuelve

- **Bus del sistema** (`/run/dbus/system_bus_socket`, 0666): sigue siendo
  legible. Es el riesgo residual que se documenta y que C02 decidirá si merece
  la pena cerrar (usuario + `bubblewrap`, o volver a una VM).
- **`/tmp` compartido**: el cliente puede leer archivos de `/tmp` con permisos
  de lectura para todos. No hay secretos ahí, pero conviene saberlo.
- **Audio**: no hay sonido. Es deliberado: darle el PipeWire del usuario
  permitiría escuchar el micrófono y mezclarse con el audio real.
- **Un fallo de Xephyr**: corre como tu usuario y con la cookie de tu display
  `:0` (la necesita para pintar), así que la jaula le quita la red, pero no el
  acceso a tus archivos ni a tu sesión X. Eso ya requeriría una VM y se asume
  como residual.

## Antes de empezar

```bash
cd ~/metin2-docs
git pull
```

- VM FreeBSD encendida; VM Windows apagada.
- Si la jaula quedó abierta de C01b, deshazla:

```bash
bash tools/c01/90-netns-down.sh
```

- Internet **no** hace falta. Solo si falta Xephyr (ver Fase 2) se instala en el
  host; eso es preparación, no el cliente.

---

## Fase 1 — Crear `metin2` y mover el laboratorio

```bash
bash tools/c01bis/10-usuario.sh 2>&1 | tee salidas/2026-11-09-c01bis-00-usuario.txt
```

Qué hace:

1. Crea el usuario `metin2` con `/home/metin2`, sin sudo y solo con los grupos
   de GPU (`render`/`video`) si existen.
2. Pone `chmod 700` en tu home real.
3. Mueve `~/metin2lab` (cliente, pack, prefijo y caché de DXVK) a
   `/home/metin2/metin2lab` y lo pone a nombre de `metin2`.
4. Crea `/run/user/<uid de metin2>`.

Debe terminar mostrando `metin2client.exe` y `OK. Siguiente: ...`.

> **Discos de VM**: `~/metin2lab` es solo del cliente. Los discos de libvirt
> viven en `/var/lib/libvirt/images` (la FreeBSD, en
> `/var/lib/libvirt/images/m2-server/`). `10-usuario.sh` aborta si encuentra
> `vm/` o algún `*.qcow2` en el laboratorio: si pasa, mueve los discos a
> `/var/lib/libvirt/images` antes de repetir. `metin2` no debe poder tocar la
> imagen del servidor.

**PARADA** si `sudo -l -U metin2` muestra algo permitido, o si el `.exe` no
aparece. Publica la salida y avisa.

---

## Fase 2 — Arrancar Xephyr (display anidado, sin red)

```bash
bash tools/c01bis/15-xephyr.sh 2>&1 | tee salidas/2026-11-09-c01bis-01-xephyr.txt
```

Qué hace:

1. Crea la jaula `m2xephyr`: un netns vacío, solo con `lo`, sin veth, sin
   rutas y sin DNS.
2. Arranca Xephyr **como tu usuario** (tiene que pintar en tu pantalla), pero
   dentro de esa jaula. Si lo comprometen, el código no tiene red.
3. Lo abre en una **ventana** de `1920x1080`, con `-no-host-grab -resizeable`:
   no captura el teclado ni el ratón del host.

Debe abrirse una ventana titulada **Metin2 (jaula C01-bis)** y el script decir
`OK: Xephyr listo en :7 dentro de m2xephyr`.

Pantalla completa es **opcional** y ya no es el modo por defecto:

```bash
FULLSCREEN=1 bash tools/c01bis/15-xephyr.sh
```

Para cerrar Xephyr sin depender de atajos:

```bash
bash tools/c01bis/16-xephyr-stop.sh
```

Si en juego la cámara del ratón da saltos, prueba a que Xephyr capture el
puntero (por defecto **no** lo hace):

```bash
bash tools/c01bis/16-xephyr-stop.sh
HOST_GRAB=1 bash tools/c01bis/15-xephyr.sh
```

Con `HOST_GRAB=1`, `Ctrl+Shift` suelta la captura y `16-xephyr-stop.sh` sigue
siendo la salida segura.

El juego se conecta a `:7` por el socket Unix `/tmp/.X11-unix/X7`, que los
netns no aíslan: por eso funciona aunque Xephyr no tenga red.

Si falta el programa:

```bash
sudo pacman -S xorg-server-xephyr
```

y repite la fase. Esto usa Internet en el **host** (preparación); la jaula del
juego sigue sin salida.

Si Xephyr no arranca dentro del netns (raro), prueba sin jaula **solo para
depurar**:

```bash
SIN_NETNS=1 bash tools/c01bis/15-xephyr.sh
```

Eso deja Xephyr con red. No es el modo normal: avísame y lo investigamos.

Detalle: en ventana no hay que «sacar» el ratón; `-no-host-grab` deja que
`Alt+Tab` y el resto del escritorio funcionen. Si arrancaste con
`FULLSCREEN=1`, la salida segura es `16-xephyr-stop.sh` desde otra terminal o
TTY (`Ctrl+Alt+F3`); no se vuelve a usar `Ctrl+Shift` como única salida.

---

## Fase 3 — Montar la jaula de red

```bash
bash tools/c01/20-netns-up.sh 2>&1 | tee salidas/2026-11-09-c01bis-02-jaula.txt
```

Debe terminar con `hosts:      files`, `OK: sin salida a Internet` y
`OK: sin DNS`. Es el mismo script de C01b, sin cambios.

---

## Fase 4 — Lanzar el cliente (Terminal A)

```bash
bash tools/c01bis/30-run-client.sh 2>&1 | tee salidas/2026-11-09-c01bis-03-cliente.txt
```

El juego aparece **dentro de la ventana de Xephyr**, corriendo como `metin2`.
Entra a la primera entrada (`Metin2`), no a `Test`, y juega un minuto.

Debe verse el HUD de DXVK con `NVIDIA GeForce GTX 1650`, igual que en C01b.
No habrá sonido: es lo esperado.

**PARADA** si la ventana no aparece, si el HUD falta, si el juego se cierra o
si el ratón/teclado no responden. Cierra y publica la salida.

---

## Fase 5 — Comprobar red y usuario (Terminal B)

Con el juego abierto:

```bash
bash tools/c01/35-check-isolation.sh 2>&1 | tee salidas/2026-11-09-c01bis-04-aislamiento.txt
bash tools/c01bis/35-check-usuario.sh 2>&1 | tee salidas/2026-11-09-c01bis-05-usuario.txt
nvidia-smi 2>&1 | tee salidas/2026-11-09-c01bis-06-gpu.txt
```

Debe verse:

- En `04`: procesos `wine`/`metin2client` en la jaula, conexiones solo a
  `10.10.10.10`, `OK: sin salida a Internet` y `OK: sin DNS`.
- En `05`: `OK` en home, bus de sesión, audio y en `m2xephyr` (solo `lo`, sin
  rutas ni DNS, Xephyr corriendo dentro); **`AVISO` en el bus del sistema** (se
  espera; es el riesgo residual).
- En `06`: `metin2client.exe` en la GTX 1650.

Si `05` dice `PELIGRO` en el home, en el bus de sesión, en audio o en la jaula
de Xephyr, **para** y publica la salida.

---

## Fase 6 — Copia dorada del cliente (btrfs)

Solo si las fases anteriores fueron bien. El progreso del juego **no** vive
aquí: está en MariaDB dentro de la FreeBSD. Esto guarda una instalación
conocida-buena del cliente (prefijo, DXVK y configuración) para volver a ella
sin reinstalar.

```bash
bash tools/c01bis/80-snapshot.sh 2>&1 | tee salidas/2026-11-09-c01bis-07-snapshot.txt
```

Qué hace:

1. Comprueba que `/home` es btrfs.
2. Convierte `/home/metin2/metin2lab` en subvolumen (si aún no lo es) y
   conserva la copia anterior en `metin2lab.pre-subvol`.
3. Crea `metin2lab-golden` en modo **read-only**.

Debe terminar mostrando los dos subvolúmenes. Si `metin2lab-golden` ya existe,
no lo pisa.

Si algún día el cliente se rompe:

```bash
bash tools/c01bis/85-reset.sh
```

Aparta el laboratorio roto en `metin2lab.roto-<fecha>` y crea uno nuevo desde
la copia dorada. No borra nada. Cuando compruebes que todo va, puedes borrar
`metin2lab.pre-subvol` con `sudo rm -rf`.

---

## Fase 7 — Cerrar y publicar

1. Cierra el juego (la Terminal A vuelve y mata su `wineserver`).
2. El log de DXVK queda en el home de `metin2` (hace falta `sudo`).
   `30-run-client.sh` ya lo copia a `~/metin2lab/logs/` al terminar; si por lo
   que sea no está, cópialo así (el glob **no** puede expandirlo tu shell,
   porque `/home/metin2` es `0700`):

```bash
cd ~/metin2-docs
sudo find /home/metin2/metin2lab/wine/prefix/drive_c/Games/Metin2/dxvk-logs \
  -maxdepth 1 -type f -name '*_d3d*.log' \
  -exec cp -f {} "$HOME/metin2lab/logs/" \; 2>/dev/null || true
sudo chown "$(id -u):$(id -g)" "$HOME"/metin2lab/logs/*_d3d*.log 2>/dev/null || true
for f in "$HOME"/metin2lab/logs/*_d3d*.log; do
  [ -f "$f" ] && { echo "== $f =="; cat "$f"; }
done >> salidas/2026-11-09-c01bis-03-cliente.txt
```

3. Deshaz las jaulas: `90` cierra Xephyr `:7`, el `wineserver` del cliente y
   borra `metin2lab` y `m2xephyr`:

```bash
bash tools/c01/90-netns-down.sh 2>&1 | tee salidas/2026-11-09-c01bis-08-cierre.txt
```

4. Publica:

```bash
for f in salidas/2026-11-09-c01bis-*.txt; do
  tools/sanitize.sh "$f"
done
git add salidas/2026-11-09-c01bis-*.txt
git commit -m "Salida C01-bis: cliente como usuario metin2 en Xephyr"
git push
```

Avisa: **«C01-bis subido»** y responde:

1. ¿Apareció el HUD igual que en C01b?
2. ¿Se nota igual de fluido dentro de Xephyr y a pantalla completa?
3. ¿`35-check-usuario` dio `OK` en home, bus de sesión, audio y `m2xephyr`?
4. ¿Salió `AVISO` en el bus del sistema?
5. ¿Te costó sacar el ratón de la ventana (Ctrl+Shift)?
6. ¿Algún aviso raro de Wine por cambiar de usuario o de perfil?
7. ¿`80-snapshot.sh` terminó y creó los dos subvolúmenes?

## Qué se considera éxito

- El juego corre como `metin2`, en Xephyr (ventana por defecto; `FULLSCREEN=1`
  opcional), con HUD de DXVK y GTX 1650.
- La red sigue cerrada: solo `10.10.10.10`, sin Internet ni DNS.
- Xephyr está dentro de `m2xephyr`: solo `lo`, sin rutas ni DNS.
- `metin2` no puede leer tu home, ni el bus de sesión, ni el audio.
- El bus del sistema aparece como `AVISO`, documentado, no oculto.
- `metin2lab-golden` existe en btrfs y `85-reset.sh` puede restaurarlo.

Si sale bien, C01-bis queda cerrado y pasamos a **C02**: decidir la topología
definitiva (usuario/jaula, si se cierra el bus del sistema con `bubblewrap`, y
qué se hace con el cliente Windows de la VM y con el portátil).

## Modo diario (después de C01-bis)

El procedimiento completo está en **`docs/06-runbook-diario.md`**. Resumen:

```bash
# 1. jaula del juego
bash tools/c01/20-netns-up.sh 2>&1 | tee salidas/dia-jaula.txt
# 2. Xephyr
bash tools/c01bis/15-xephyr.sh 2>&1 | tee salidas/dia-xephyr.txt
# 3. cliente
bash tools/c01bis/30-run-client.sh 2>&1 | tee salidas/dia-cliente.txt
# 4. al terminar de jugar: cierre completo
bash tools/c01/90-netns-down.sh 2>&1 | tee salidas/dia-cierre.txt
```

- `20` reutiliza `metin2lab`; `15` reutiliza `m2xephyr` y Xephyr si ya están.
- `30` mata el `wineserver` viejo y lanza el cliente dentro.
- Las jaulas y Xephyr desaparecen al reiniciar.
- `90` es el cierre normal (Xephyr + wineserver + las dos jaulas). `16` solo
  cierra Xephyr, para cambiar de modo o como salida de emergencia.
- `10-usuario.sh` y `80-snapshot.sh` **no** se repiten: son de una sola vez.

## Si falla

| Síntoma | Qué hacer |
|---|---|
| `10-usuario.sh` no mueve el laboratorio | Comprueba espacio y que `~/metin2lab` existe. Si el `mv` falló a medias, no repitas a ciegas: publica la salida. |
| Wine se queja del prefijo o del perfil (`users/deadivine`) | Recrea el prefijo como `metin2` con las fuentes ya movidas (ver abajo). |
| Xephyr no arranca | Mira `/tmp/xephyr-c01bis.log`. Comprueba que `DISPLAY=:0` funciona en tu sesión. |
| Xephyr no arranca dentro de `m2xephyr` | Prueba **solo para depurar** `SIN_NETNS=1 bash tools/c01bis/15-xephyr.sh`. Si así funciona, publica `01-xephyr.txt` y el log; no lo dejes como modo normal. |
| `35-check-usuario` dice que Xephyr está fuera de `m2xephyr` | `bash tools/c01/90-netns-down.sh` y repite `15`. Si insiste, no sigas: publica la salida. |
| La ventana de Xephyr sale negra | El juego aún no ha pintado. Espera o revisa `03-cliente.txt`. |
| El ratón no sale de Xephyr | No debería pasar: `15` arranca con `-no-host-grab`. Si pasó, `Ctrl+Alt+F3`, `bash tools/c01bis/16-xephyr-stop.sh` y comprueba que el script tiene esa opción. |
| Xephyr se queda a pantalla completa sin salida | `Ctrl+Alt+F3`, inicia sesión en TTY, `bash tools/c01bis/16-xephyr-stop.sh`, y vuelve con `Ctrl+Alt+F1`. |
| HUD ausente otra vez | No toques DXVK: mira el log `*_d3d*.log` y publica `03-cliente.txt` + el log. |
| No hay sonido | Es lo esperado. No añadas el PipeWire del usuario sin hablarlo antes. |
| `80-snapshot.sh` dice que no es btrfs | Comprueba `findmnt -no FSTYPE /home`. No fuerces la conversión: publica la salida. |
| `85-reset.sh` dice que no hay copia dorada | Ejecuta antes `80-snapshot.sh` y revisa que `metin2lab-golden` existe. |

Recrear el prefijo como `metin2` (solo si Wine falla al cambiar de usuario):

```bash
sudo cp -a ~/metin2-docs/tools /home/metin2/metin2lab/
sudo chown -R metin2:metin2 /home/metin2/metin2lab/tools
sudo -u metin2 env HOME=/home/metin2 DISPLAY=:7 \
  bash /home/metin2/metin2lab/tools/c01/10-prefix.sh
sudo -u metin2 env HOME=/home/metin2 DISPLAY=:7 \
  bash /home/metin2/metin2lab/tools/c01/15-dxvk.sh
```

Las fuentes (`tmp4/`) y el pack (`work/b04/`) ya están dentro de
`/home/metin2/metin2lab`, así que no hace falta Internet.
