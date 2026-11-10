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
real.

## Qué NO resuelve

- **Bus del sistema** (`/run/dbus/system_bus_socket`, 0666): sigue siendo
  legible. Es el riesgo residual que se documenta y que C02 decidirá si merece
  la pena cerrar (usuario + `bubblewrap`, o volver a una VM).
- **`/tmp` compartido**: el cliente puede leer archivos de `/tmp` con permisos
  de lectura para todos. No hay secretos ahí, pero conviene saberlo.
- **Audio**: no hay sonido. Es deliberado: darle el PipeWire del usuario
  permitiría escuchar el micrófono y mezclarse con el audio real.

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

**PARADA** si `sudo -l -U metin2` muestra algo permitido, o si el `.exe` no
aparece. Publica la salida y avisa.

---

## Fase 2 — Arrancar Xephyr (display anidado)

```bash
bash tools/c01bis/15-xephyr.sh 2>&1 | tee salidas/2026-11-09-c01bis-01-xephyr.txt
```

Debe abrirse una ventana vacía titulada **Metin2 (jaula C01-bis)** y el script
decir `OK: Xephyr listo en :7`.

Si falta el programa:

```bash
sudo pacman -S xorg-server-xephyr
```

y repite la fase. Esto usa Internet en el **host** (preparación); la jaula del
juego sigue sin salida.

Detalle: para sacar el ratón de la ventana de Xephyr, pulsa **Ctrl+Shift**.

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
- En `05`: `OK` en home, bus de sesión y audio; **`AVISO` en el bus del
  sistema** (se espera; es el riesgo residual).
- En `06`: `metin2client.exe` en la GTX 1650.

Si `05` dice `PELIGRO` en el home, en el bus de sesión o en audio, **para** y
publica la salida.

---

## Fase 6 — Cerrar y publicar

1. Cierra el juego (la Terminal A vuelve y mata su `wineserver`).
2. Copia el log de DXVK (está en el home de `metin2`, hace falta `sudo`) y
   pégalo al final de la salida del cliente:

```bash
cd ~/metin2-docs
sudo cp /home/metin2/metin2lab/wine/prefix/drive_c/Games/Metin2/dxvk-logs/*_d3d*.log ~/metin2lab/logs/ 2>/dev/null || true
for f in ~/metin2lab/logs/*_d3d*.log; do
  [ -f "$f" ] && { echo "== $f =="; cat "$f"; }
done >> salidas/2026-11-09-c01bis-03-cliente.txt
```

3. Deshaz la jaula y cierra Xephyr:

```bash
bash tools/c01/90-netns-down.sh
pkill -f 'Xephyr :7' || true
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
2. ¿Se nota igual de fluido dentro de Xephyr?
3. ¿`35-check-usuario` dio `OK` en home, bus de sesión y audio?
4. ¿Salió `AVISO` en el bus del sistema?
5. ¿Te costó sacar el ratón de la ventana (Ctrl+Shift)?
6. ¿Algún aviso raro de Wine por cambiar de usuario o de perfil?

## Qué se considera éxito

- El juego corre como `metin2`, en Xephyr, con HUD de DXVK y GTX 1650.
- La red sigue cerrada: solo `10.10.10.10`, sin Internet ni DNS.
- `metin2` no puede leer tu home, ni el bus de sesión, ni el audio.
- El bus del sistema aparece como `AVISO`, documentado, no oculto.

Si sale bien, C01-bis queda cerrado y pasamos a **C02**: decidir la topología
definitiva (usuario/jaula, si se cierra el bus del sistema con `bubblewrap`, y
qué se hace con el cliente Windows de la VM y con el portátil).

## Si falla

| Síntoma | Qué hacer |
|---|---|
| `10-usuario.sh` no mueve el laboratorio | Comprueba espacio y que `~/metin2lab` existe. Si el `mv` falló a medias, no repitas a ciegas: publica la salida. |
| Wine se queja del prefijo o del perfil (`users/deadivine`) | Recrea el prefijo como `metin2` con las fuentes ya movidas (ver abajo). |
| Xephyr no arranca | Mira `/tmp/xephyr-c01bis.log`. Comprueba que `DISPLAY=:0` funciona en tu sesión. |
| La ventana de Xephyr sale negra | El juego aún no ha pintado. Espera o revisa `03-cliente.txt`. |
| El ratón no sale de Xephyr | Ctrl+Shift. Si no, cierra el juego y `pkill -f 'Xephyr :7'`. |
| HUD ausente otra vez | No toques DXVK: mira el log `*_d3d*.log` y publica `03-cliente.txt` + el log. |
| No hay sonido | Es lo esperado. No añadas el PipeWire del usuario sin hablarlo antes. |

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
