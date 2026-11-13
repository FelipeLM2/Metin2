# Runbook diario

Procedimiento corto para **jugar y cerrar sin dejar nada abierto**. Los
detalles de por qué existe cada pieza están en `docs/02-entorno.md` y
`docs/05-seguridad.md`; esto es solo la lista de comandos.

Hay **dos jaulas** y no son lo mismo:

| Nombre | Quién la crea | Para qué |
|---|---|---|
| `metin2lab` | `tools/c01/20-netns-up.sh` | red del juego: una sola ruta a `10.10.10.10`, sin Internet ni DNS |
| `m2xephyr` | `tools/c01bis/15-xephyr.sh` | red de Xephyr: solo `lo`, ninguna salida |
| `:7` | `15-xephyr.sh` | pantalla anidada donde aparece el juego |
| `/home/metin2/metin2lab` | `10-usuario.sh` (una vez) | prefijo de Wine, cliente y copia de trabajo |

Orden: **servidor → jaula del juego → Xephyr → cliente**. El orden de la jaula
y Xephyr da igual, pero si uno falla no abras el siguiente.

---

## 0. Encender el servidor (una vez por sesión)

La VM y el servidor pueden quedarse encendidos entre partidas; si ya lo están,
salta al paso 1.

```bash
sudo virsh -c qemu:///system start m2-server     # o desde virt-manager
ssh root@10.10.10.10 hostname                    # debe responder sin pedir nada raro
ssh root@10.10.10.10
```

Dentro de la FreeBSD:

```sh
cd /usr/metin2/server
sh start.sh        # opción 1 = un canal
```

Comprobar los puertos (desde CachyOS, en otra terminal):

```bash
ssh root@10.10.10.10 "sockstat -4 -l | grep -E ':11000|:13001|:15000'"
```

Deben salir `11000` (auth), `13001` (canal) y `15000` (db, en loopback).

> La jaula `metin2lab` necesita el puente `virbr-lab`, que crea libvirt al
> arrancar la VM. Por eso el servidor va primero.

---

## 1. Jaula del juego

```bash
cd ~/metin2-docs
bash tools/c01/20-netns-up.sh 2>&1 | tee salidas/dia-jaula.txt
```

Debe terminar con:

```
OK: sin salida a Internet
OK: sin DNS
```

y arriba, en las rutas, **no** debe aparecer `default`.

**PARADA** si dice `PELIGRO`. No lances el cliente.

---

## 2. Xephyr (pantalla anidada)

```bash
bash tools/c01bis/15-xephyr.sh 2>&1 | tee salidas/dia-xephyr.txt
```

Debe decir `OK: Xephyr listo en :7 dentro de m2xephyr` y abrir una ventana
titulada **Metin2 (jaula C01-bis)**.

- El bus del sistema se enmascara solo en el namespace de Xephyr
  (`19-sin-bus.sh`): en el log debe aparecer
  `OK: bus del sistema enmascarado`. Si el montaje no funciona, `15` para en
  vez de arrancar sin él.
- Por defecto va **en ventana** y no captura el teclado ni el ratón: `Alt+Tab`
  funciona.
- Si la cámara del juego da saltos, prueba la captura de ratón:

```bash
bash tools/c01bis/16-xephyr-stop.sh
HOST_GRAB=1 bash tools/c01bis/15-xephyr.sh
```

- Para pantalla completa (opcional): `FULLSCREEN=1 bash tools/c01bis/15-xephyr.sh`.
  La salida segura sigue siendo `16-xephyr-stop.sh`.

---

## 3. Cliente (Terminal A)

```bash
bash tools/c01bis/30-run-client.sh 2>&1 | tee salidas/dia-cliente.txt
```

La terminal se queda ocupada: el cliente corre en primer plano. Entra a la
primera entrada (`Metin2`), no a `Test`.

- El HUD de DXVK debe mostrar `NVIDIA GeForce GTX 1650`.
- No hay sonido: es lo esperado.
- Al salir del juego, la terminal vuelve y el script cierra su `wineserver`.

Comprobaciones opcionales mientras juegas (Terminal B):

```bash
bash tools/c01/35-check-isolation.sh 2>&1 | tee salidas/dia-aislamiento.txt
bash tools/c01bis/35-check-usuario.sh 2>&1 | tee salidas/dia-usuario.txt
```

Debe salir `OK` en red, home, bus de sesión, **bus del sistema**, audio y
`m2xephyr`. El bus del sistema se comprueba **dentro** del namespace del
cliente; si `35` imprime `PELIGRO` ahí, es que el proceso se lanzó con
`SIN_BUS=1` (mal) o el montaje no se aplicó.

---

## 4. Cerrar (siempre)

1. Sal del juego con su menú normal (o cierra su ventana).
2. Cuando vuelva la Terminal A:

```bash
bash tools/c01/90-netns-down.sh 2>&1 | tee salidas/dia-cierre.txt
```

Eso cierra Xephyr `:7`, el `wineserver` del cliente y **borra las dos jaulas**.
Es el cierre recomendado: la próxima sesión empieza limpia.

```bash
# Solo si quieres cerrar Xephyr pero seguir usando las jaulas:
bash tools/c01bis/16-xephyr-stop.sh
```

3. Opcional: parar el servidor y la VM.

```bash
ssh root@10.10.10.10 "cd /usr/metin2/server && sh close.sh"
sudo virsh -c qemu:///system shutdown m2-server
```

> Las jaulas y Xephyr **no sobreviven a un reinicio**. Si reiniciaste, empieza
> en el paso 1 (no hace falta repetir `10-usuario.sh` ni `80-snapshot.sh`).

---

## 5. Si ya está todo abierto y solo quieres volver a jugar

- Se cerró el juego pero siguen las jaulas y Xephyr: `bash tools/c01bis/30-run-client.sh`.
- Se cerró Xephyr pero sigue la jaula: `bash tools/c01bis/15-xephyr.sh`.
- Se borró la jaula (o reiniciaste): paso 1 completo.

`30-run-client.sh` mata el `wineserver` viejo antes de lanzar; no hace falta
hacerlo a mano.

---

## Una sola vez (ya hecho)

No se repiten en el día a día:

| Script | Qué dejó hecho |
|---|---|
| `tools/c01bis/10-usuario.sh` | usuario `metin2`, laboratorio movido a su home, tu home en `700` |
| `tools/c01bis/80-snapshot.sh` | `metin2lab` como subvolumen y `metin2lab-golden` read-only |

Si el prefijo se rompe: `bash tools/c01bis/85-reset.sh` (aparta el roto y
restaura desde la copia dorada; no borra nada). **No borres `metin2lab-golden`**
ni `metin2lab.pre-subvol` hasta comprobar que la copia dorada arranca bien.

---

## Render, FPS y ratón (estado conocido)

Medido en C01-bis (2026-11-11): el HUD marca **~25 FPS** dentro de Xephyr,
frente a **50/60** del mismo cliente en `:0` (C01b). La GPU no es el límite:
`nvidia-smi` muestra el `metin2client.exe` en la GTX 1650 con ~210 MiB.

Lo que dice el log del cliente:

- DXVK v3.1.1, GTX 1650, `VK_PRESENT_MODE_IMMEDIATE_KHR`, 3 imágenes,
  ventana de 1920×918.
- Xephyr **no tiene DRI3** (`MESA-EGL: DRI3 error`): es un servidor X por
  software. La sesión es Wayland (`kwin_wayland`), así que la cadena real es
  juego → Xephyr → Xwayland → KWin: cada fotograma pasa por más copias que en
  `:0`, donde DXVK presenta casi directo. El HUD de DXVK mide la tasa real de
  presentación, no un número inventado del juego.
- Las líneas `FrameSkip` también aparecían en C01b, así que por sí solas no
  explican la caída.

El ratón "errático" en juego es otro efecto del display anidado: con
`-no-host-grab`, cuando el juego captura el puntero, el cursor del host puede
salir de la ventana y Xephyr deja de recibir movimiento; al volver, la cámara
salta. `HOST_GRAB=1` activa la captura (Ctrl+Shift la suelta).

Ideas para probar, **una cada vez** y apuntando el resultado:

1. `FULLSCREEN=1 bash tools/c01bis/15-xephyr.sh` (puede ahorrar alguna
   composición; la salida segura ya existe).
2. `GEOM=1280x720 bash tools/c01bis/15-xephyr.sh` (menos píxeles por copia;
   es la prueba con más probabilidad de acercarse a 60).
3. `HOST_GRAB=1` para el ratón.
4. Durante la partida: `top` (¿cuánto come `Xephyr`/`Xwayland`/`kwin_wayland`?)
   y `nvidia-smi` (¿la GPU está al 100% o al 35%?).
5. Si no necesitas al agente mientras juegas, apaga su VM Windows: son 2 vCPU
   y 4 GB que compiten con el host.

> **Cámara: aparcada.** El primer intento (`14-xephyr-warp.sh`) no arregló el
> arrastre con el botón derecho y no está confirmado que el parche compilara.
> No se dedica más tiempo por ahora; se retomará pidiendo la salida completa del
> build. Mientras tanto, la cámara sigue como en C01-bis y el `AVISO` de
> `14` en `15` (**`Camara: si da saltos...`**) es esperado si no existe
> `~/.local/bin/Xephyr`.

---

## Fallos rápidos

| Síntoma | Qué hacer |
|---|---|
| `20` dice que no existe `virbr-lab` | la VM FreeBSD no está arrancada: `sudo virsh start m2-server`. |
| `30` dice que no existe la jaula | paso 1: `bash tools/c01/20-netns-up.sh`. |
| `30` dice que no existe `:7` | paso 2: `bash tools/c01bis/15-xephyr.sh`. |
| `15` o `30` dicen que `unshare --mount` no funciona | kernel sin permisos para mount ns: para y publica la salida. `SIN_BUS=1` solo para depurar. |
| `15` dice que Xephyr ya está | ya está corriendo; sigue en `30`, o ciérralo con `16` para cambiar de modo. |
| La ventana de Xephyr sale negra | el cliente aún no ha pintado; espera o mira `salidas/dia-cliente.txt`. |
| El ratón se queda dentro de Xephyr | `Ctrl+Shift`; si no, `Ctrl+Alt+F3`, `bash tools/c01bis/16-xephyr-stop.sh`, vuelve con `Ctrl+Alt+F1`. |
| El juego no pasa del login | comprueba los puertos del servidor (`sockstat`) y que `35-check-isolation` vea `10.10.10.10`. |
| `35-check-usuario` dice `PELIGRO` | para y publica la salida; no sigas jugando. |
| `90` avisa de procesos dentro de la jaula | el script intenta cerrarlos; si insiste, `sudo ip netns pids metin2lab` y publica. |

Reglas que no cambian: el cliente **nunca** como root, nada de `Z:` ni carpetas
compartidas, sin audio, y si un script dice `PELIGRO`, se para.
