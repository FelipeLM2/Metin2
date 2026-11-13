# C01-bis — Cliente con usuario Linux aparte

C01 dejó el cliente funcionando en CachyOS (Wine + DXVK, jaula de red). C01-bis
quita el último privilegio del `.exe`: deja de correr como el usuario real.

| Aspecto | C01/C01b | C01-bis |
|---|---|---|
| Usuario | `deadivine` | `metin2` (sin sudo; solo `render`/`video` para la GPU) |
| Home | el real | `/home/metin2` (0700) |
| X11 | display `:0` (el escritorio) | Xephyr `:7` (X anidado, solo su ventana) |
| Red de Xephyr | la del usuario | netns `m2xephyr` (solo `lo`, sin rutas ni DNS) |
| Audio | el del usuario | sin audio (a propósito) |
| Portapapeles | el de `:0` | separado (Xephyr no lo sincroniza) |
| Bus de sesión | no se pasa | inaccesible (socket 0600) |
| Bus del sistema | visible | enmascarado en el mount ns (`19-sin-bus.sh`) |
| Red del juego | netns `metin2lab` | igual |

Los dos netns están separados: el juego vive en `metin2lab` (veth →
`10.10.10.10`) y Xephyr en `m2xephyr` (sin ninguna interfaz de red). Se
comunican por el socket X de `/tmp/.X11-unix/X7`, que los netns no aíslan.

Scripts, en este orden, desde `~/metin2-docs`:

| Script | Qué hace | ¿Internet? |
|---|---|---|
| `10-usuario.sh` | Crea `metin2`, mueve `~/metin2lab` a su home y protege el real | no |
| `14-xephyr-warp.sh` | Compila e instala `~/.local/bin/Xephyr` con el warp real (arregla la cámara) | sí (tarball oficial) |
| `15-xephyr.sh` | Crea `m2xephyr` y arranca Xephyr `:7` en ventana (1080p) dentro de él | no |
| `16-xephyr-stop.sh` | Cierra solo el Xephyr `:7` (salida de emergencia; no toca jaulas) | no |
| `19-sin-bus.sh` | Helper: enmascara `/run/dbus/system_bus_socket` y baja a `metin2` (lo llaman 15 y 30) | no |
| `../c01/20-netns-up.sh` | Crea la jaula de red del juego (reutilizado) | no |
| `30-run-client.sh` | Lanza el cliente como `metin2` en `:7` y en `metin2lab` | no |
| `32-game-res.sh` | Resolucion y ventana/pantalla completa del cliente (`metin2.cfg`) | no |
| `../c01/35-check-isolation.sh` | Red: rutas, conexiones, Internet, DNS | no |
| `35-check-usuario.sh` | Usuario: home, sudo, bus, audio y jaula `m2xephyr` | no |
| `80-snapshot.sh` | Convierte el laboratorio en subvolumen btrfs y crea `metin2lab-golden` | no |
| `85-reset.sh` | Restaura `metin2lab` desde la copia dorada | no |

Reglas que no cambian:

- Nada de ejecutar el cliente como root.
- Nada de `Z:` ni de carpetas compartidas.
- La jaula del juego sigue con una única ruta a `10.10.10.10/32` y sin DNS.
- Xephyr corre como el usuario real (pinta en la pantalla), pero sin red.
- **El bus del sistema queda enmascarado.** `15` y `30` se envuelven en
  `unshare --mount` + `19-sin-bus.sh`, que hace `mount --bind /dev/null
  /run/dbus/system_bus_socket` dentro de ese namespace. No toca el host ni
  instala nada. Si el montaje no es posible, el script para en vez de arrancar
  sin él. `SIN_BUS=1` lo deja visible solo para depurar.
- Si `35-check-usuario.sh` imprime `PELIGRO`, para y avisa.
- `90-netns-down.sh` es el **cierre normal**: Xephyr + wineserver + las dos
  jaulas. `16-xephyr-stop.sh` cierra solo Xephyr (cambio de modo o emergencia).
- **Los discos de las VMs no viven en `metin2lab`.** Van en
  `/var/lib/libvirt/images`; `metin2` ejecuta un `.exe` sin auditar y no debe
  poder tocar la imagen del servidor. `10-usuario.sh` aborta si los encuentra.
- Xephyr arranca en **ventana** y con `-no-host-grab`: no secuestra el
  teclado/ratón del host. `FULLSCREEN=1` es opcional; para salir,
  `16-xephyr-stop.sh`.
- La cámara del juego (arrastrar con el botón derecho) necesita que el servidor
  X mueva el puntero **real**: el cliente hace `GetCursorPos` en cada frame y
  recentra con `SetCursorPos` al punto donde pulsaste. El Xephyr de pacman solo
  mueve su puntero interno (la cámara da saltos). `14-xephyr-warp.sh` compila un
  Xephyr parcheado en `~/.local/bin/Xephyr` que reenvía ese warp al servidor
  real; `15-xephyr.sh` lo usa solo si existe. No toca paquetes: para volver
  atrás, `rm -f ~/.local/bin/Xephyr`.
  **Estado: aparcado.** El primer intento no arregló la cámara y no está
  confirmado que el parche llegara a compilarse. No se dedica más tiempo por
  ahora; si se retoma, pedir la salida completa del build antes de tocar nada.
- Si `14-xephyr-warp.sh` no compila o la cámara sigue mal, el plan de respaldo
  es jugar en `:0` como `metin2` (la red sigue enjaulada, pero se pierde el
  aislamiento de pantalla y portapapeles).
