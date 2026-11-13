# Bitácora

Registro cronológico. Lo importante no es el detalle técnico (eso está en los
demás documentos), sino **qué se decidió, qué falló y por qué**.

---

## 2026-11-05 — Puesta en marcha

- Auditoría de la VM FreeBSD: 13.5-RELEASE i386, host `metin2.code`,
  MariaDB 10.6.21, sin `crontab` ni claves SSH ajenas, 7 GB usados de 46.
- IP estática `10.10.10.10/24` verificada en `rc.conf`, sin `defaultrouter`.
- Servidor arrancado por primera vez con `start.sh` (opción 1):
  auth en `11000`, game en `13000`/`13001`/`13099`, db en `15000`.
- Cliente Windows instalado limpio (Home x64, SATA, sin red durante el OOBE)
  y luego conectado a la red aislada con IP `10.10.10.20`.
- **Hallazgo**: la IP del servidor no está en `metin2.cfg` (eso es solo
  vídeo): está en `pack/root/serverinfo.py`, dentro de `root.epk`, que está
  comprimido (LZO) y cifrado (XTEA). Nada legible con `grep`.
- Primer acceso al juego con un `netsh interface portproxy` de `127.0.0.1` a
  `10.10.10.10`. Eso confirmó que el pack apunta a loopback.
- Lag alto y ratón extraño: render por software a 1920×1002, y el dispositivo
  "tablet" de virt-manager. Se bajó a 1280×720, sombras a 0 y se quitó el
  tablet. Mejoró.
- Snapshots: `servidor-arranca` y del cliente.

## 2026-11-06 — Fase A: servidor propio

- Backup: `mysqldump` de las 5 bases + copia de `game`/`db` y sus SHA256.
- Compilado `db` (~2 min) y `game` (~30 min) con `-j3`, 8 GB de RAM.
  Ambos terminan en `All done` y el Makefile los mueve a `share/bin`.
- **El build es reproducible**: los SHA256 son idénticos a los binarios de
  fábrica. Los ejecutables distribuidos son el build de las fuentes incluidas.
- Credenciales rotadas: root de FreeBSD, root de MariaDB, `admin` del juego
  (hash `PASSWORD()`, 41 caracteres).
- **Hallazgo de seguridad**: `bind-address = *` (MariaDB en 0.0.0.0:3306) y
  `root@%` conservando la contraseña de fábrica. Se comprobó conectando desde
  `10.10.10.10` con la clave vieja: respondía.
  - Corregido: `bind-address = 127.0.0.1`, `root@%` y cuentas anónimas
    eliminadas. Tras el cambio, la conexión remota ya no llega al puerto.
- Login verificado tras cada cambio. Snapshot `credenciales-ok`.

## 2026-11-07 — Repositorio y Fase B

- Creado el repositorio como cuaderno del proyecto: solo documentación,
  scripts propios y notas. Sin assets, binarios, `.sql` ni configuraciones con
  credenciales.
- **Fase B arranca** con una regla: leer primero el código de
  `ClientVS22/source/EterPack` (formato, claves XTEA, CRC) y escribir la
  herramienta propia después. Nada de unpackers de foro.
- Estrategia prevista: el índice cifrado mide 17.292 B = 12 + 90×192, el mismo
  tamaño que un índice plano `EPKD`; se puede reescribir en claro y añadir
  `serverinfo.py` al `.epk` como tipo 0 (sin LZO ni XTEA), sin tocar los otros
  89 archivos.
- Pendiente: reconocimiento de la fuente en CachyOS.

## 2026-11-08 — Fase B: pack propio y cliente sin portproxy

- `m2pack` ya lee y **escribe** el pack real: el `set` comprime con LZO (tipo 1,
  como el original) y reescribe el índice en claro.
- **Hallazgo**: los dos `long` de tamaño del índice van al revés de lo que
  declara `ClientVS22`. En el pack real, offset 172 = blob y 176 = hueco
  (múltiplo de 256). `m2pack` ya no asume el orden: el menor es el blob real.
  Eso era lo que hacía fallar `verify` en el `item_proto` y en `serverinfo.py`.
- `SERVER_IP` parcheado de `192.168.0.122` a `10.10.10.10` sobre una copia.
  `serverinfo.py` pasa de 1694 a 1689 B; el blob queda en 701 B dentro de su
  hueco de 768, así que no se mueve nada más del `.epk`.
- La copia pasa `verify` **antes y después**, y el `diff` es de una sola línea.
- El cliente arrancó y se entró al juego con el pack nuevo y el `portproxy`
  quitado, según el usuario. La transcripción del cliente se perdió por un
  fallo de `Start-Transcript` + `Read-Host`, así que la constancia queda
  pendiente en **B05**.
- B05 intentó la constancia con `*> $log`, pero el archivo tampoco llegó al
  disco FAT de retorno. **Lección**: la salida del cliente no es un canal
  fiable (ni portapapeles ni disco compartido), y no hace falta que lo sea. La
  prueba se mueve al **servidor**: `tcpdump` en `em0` mientras el cliente
  entra, más `netsh portproxy reset` justo antes del login. Si el login
  funciona con el redirector vacío, el pack nuevo es el que se usa.
- B06 lo confirmó al revés: `tcpdump` no vio **ni un paquete** y el `root.eix`
  del cliente seguía en **2968 B**. El bloque de B04 se había abortado antes de
  copiar (con `$ErrorActionPreference = "Stop"` y sin mirar si la ISO estaba
  montada), y el login de entonces fue por el `portproxy`. **Lección**: las
  copias al cliente se hacen con Explorer y se comprueban a ojo (17.292 B);
  los scripts mudos esconden el fallo.
- **B07 cierra la Fase B.** Copia manual por Explorer (17.292 B), `portproxy`
  vacío y login correcto. La captura en `em0` muestra la sesión establecida
  `10.10.10.20 ↔ 10.10.10.10:13002` durante 14 s (80 paquetes, 0 perdidos).
- **La lista de servidores fue la prueba inesperada**: antes entraba solo
  *Test* (`SERVER_IP_TEST = 127.0.0.1` + `portproxy`) y la primera entrada
  (`192.168.0.122`) no; ahora entra la primera (`10.10.10.10`) y *Test* no. Los
  papeles se invirtieron exactamente como debían.
- La entrada *Test* se queda como está: es el recordatorio de que el segundo
  servidor apunta a loopback. Documentado en `docs/02-entorno.md`.

## 2026-11-09 — C01: cliente Wine + DXVK enjaulado

- **Problema**: el lag del cliente no viene del servidor ni del pack, sino de
  que la VM Windows no tiene GPU y el cliente dibuja con **WARP** (DirectX por
  software). Cualquier cosa con aceleración real lo arregla.
- **Decisión**: probar el cliente **nativo en CachyOS** con Wine + DXVK (la
  GTX 1650 sí soporta Vulkan; el HD 4000 del portátil no). Sin comprar nada.
- **Aislamiento elegido**: mismo usuario Linux + `ip netns` (no `firejail`,
  que es SUID root y acumula CVEs de escalada). `ip netns` es kernel +
  `iproute2`, no un binario privilegiado de terceros.
- **Diseño de red**: `veth` colgada de `virbr-lab`, `10.10.10.20/32` y una
  única ruta a `10.10.10.10/32`. Sin `default`, sin DNS (`resolv.conf` vacío)
  e IPv6 desactivado. No es un firewall: dentro de la jaula **no existe** la
  interfaz hacia Internet.
- **Archivos**: se quita la unidad `Z:` (Wine mapea `/` por defecto) y el
  cliente se copia dentro del prefijo, en `C:\Games\Metin2`. No hay carpeta
  compartida, ni CD-ROM, ni portapapeles: el cliente vive en la misma máquina
  que el host, así que se copia con `cp`.
- **Internet**: solo durante la preparación (descargar DXVK). El juego se
  ejecuta siempre dentro de la jaula, sin salida. Aprobado explícitamente.
- **VM Windows**: se apaga durante la prueba (libera `10.10.10.20` y RAM); no
  se borra, queda de respaldo. El cliente original de la VM no se toca.
- **Riesgo residual aceptado**: al correr con el mismo usuario, un exploit
  nativo podría leer archivos con rutas de Linux, y X11 permite inyectar teclas
  o leer el portapapeles. Si C01 funciona, C01-bis añade un usuario `metin2`
  con su propio `/home`. La red sí queda cerrada desde el primer intento.
- Se documenta en `docs/05-seguridad.md` y se escriben los scripts en
  `tools/c01/`.

## 2026-11-09 — C01 ejecutado: casi nativo, con dos cabos sueltos

- **El cliente arranca y se juega.** Ventana, login y partida sin problemas;
  el lag de la VM desaparece («casi nativo») y el ratón va bien. La captura de
  FreeBSD ve la sesión desde `10.10.10.20` (auth `11000`, canal `13000`) y nada
  más. La jaula de red aguanta: sin ruta por defecto y `curl` a Internet falla.
- **Pero el HUD de DXVK nunca apareció.** `nvidia-smi` ve
  `metin2client.exe` con 56 MiB en la GTX 1650, pero eso solo prueba que la
  GPU trabaja, no qué renderer se usa.
- **Causa**: Wine 11.21 con WoW64 ya no crea prefijos `win32`; el prefijo es
  `win64`. `15-dxvk.sh` copió las DLL **de 32 bits** a `system32`, cuando en un
  prefijo `win64` van a `syswow64`. El cliente de 32 bits no las encontró y
  Wine usó su `wined3d` sobre OpenGL. De ahí el buen rendimiento sin HUD.
- **Segundo hallazgo**: `35` dijo `PELIGRO` en DNS. No era salida a Internet
  (sin ruta no hay conectividad): `getent` resolvía nombres por `nss-resolve`
  contra el `systemd-resolved` del host, vía D-Bus. Vaciar `resolv.conf` no
  desactiva los módulos de `nsswitch.conf`.
- **Decisión**: no se rehace nada desde cero. C01b reinstala DXVK en
  `syswow64`/`system32` desde la caché (sin Internet), monta un
  `nsswitch.conf` con `hosts: files` dentro de la jaula y vuelve a lanzar el
  cliente. El HUD y el log de DXVK serán la prueba; `nvidia-smi` no basta.
- El usuario prefirió no tocar nada durante la partida y reportar después. La
  salida y sus notas quedan en `salidas/2026-11-09-c01-*`.

## 2026-11-09 — C01b: DXVK real, DNS cerrado; C01 queda cerrado

- `15-dxvk.sh` reinstaló DXVK desde la caché (sin Internet): `d3d8`, `d3d9` y
  `dxgi` a `syswow64` (32 bits) y `system32` (64 bits). `16` confirmó
  `#arch=win64`, `syswow64` y DLLs de varios MB.
- **El HUD apareció** con `NVIDIA GeForce GTX 1650`; el log
  `metin2client_d3d9.log` dice `DXVK: v3.1.1` y
  `Found device: NVIDIA GeForce GTX 1650 (NVIDIA 615.78.8)`. El juego usa
  **D3D8** sobre DXVK (avisos `D3D8Device::SetRenderState`).
- Los imports del `.exe` salen vacíos porque el cliente carga `d3d8.dll` de
  forma dinámica. La prueba del renderer es el HUD y el log, no `objdump`.
- `20` montó `hosts: files` y dijo `OK: sin DNS`. `35` mostró las conexiones
  del cliente (`13000` y `13002`) desde `10.10.10.20`, con `OK` en Internet y
  DNS. `nvidia-smi` vio 236 MiB en la GTX 1650.
- El usuario nota **más fluidez** que en C01 y la ventana se maximiza. Tuvo que
  crear la jaula desde cero (`20`); no hizo falta `90`.
- **Decisión**: C01 queda cerrado. C01-bis mueve el cliente a un usuario Linux
  `metin2` con Xephyr (display anidado), sin audio ni bus de sesión. El bus del
  sistema seguirá visible como riesgo residual; C02 decidirá si se cierra con
  `bubblewrap` o si se vuelve a una VM.

## 2026-11-09 — C01-bis escrito: Xephyr sin red y copia dorada

- **Xephyr no es un sandbox**, pero sí cambia capacidades: el juego no ve las
  ventanas del escritorio ni su portapapeles X. Es un proceso normal (no una
  VM): a 1080p usa ~8 MB de framebuffer y algo de CPU por copia; la GPU la usa
  DXVK directamente.
- **Riesgo cerrado**: Xephyr corre como el usuario real (necesita pintar en
  `:0`) pero dentro del netns `m2xephyr`, que solo tiene `lo` y DNS cerrado.
  Si lo comprometen, no tiene LAN ni Internet. El juego sigue en `metin2lab` y
  llega a `:7` por el socket Unix de `/tmp`, que cruza netns.
- **Residual asumido**: un fallo de Xephyr sigue ejecutándose como el usuario
  real (puede leer archivos y usar la cookie de `:0`, no red); el bus del
  sistema y `/tmp` siguen visibles. Xephyr no comparte el portapapeles con `:0`
  por defecto; el puente habría que añadirlo aparte. Contra un exploit de
  kernel solo hay VM o hardware aparte.
- **Pantalla completa 1080p**: `-screen 1920x1080 -fullscreen` (revisado el
  2026-11-10: pasa a ventana por defecto). Xephyr no fija
  los 144 Hz: la cadena DXVK → Xephyr → KWin → monitor decide; se mide con el
  HUD (`DXVK_HUD=fps`). Si algún día vuelve a 1440p, `GEOM=2560x1440`.
- **Snapshots**: `/home` es btrfs. `80-snapshot.sh` convierte
  `/home/metin2/metin2lab` en subvolumen y crea `metin2lab-golden` read-only;
  `85-reset.sh` restaura apartando el actual. El progreso del juego no está
  ahí: vive en MariaDB dentro de la FreeBSD.
- **Modo diario**: `15` reutiliza `m2xephyr` y `20` reutiliza `metin2lab`.
  (Revisado el 2026-11-11: el cierre normal es `90`, que cierra Xephyr, el
  `wineserver` y borra las dos jaulas; `16` solo cierra Xephyr.)
- **VM Windows**: se archiva (disco + XML + notas), no se borra. Sigue siendo
  la única frontera barata contra un exploit de kernel.
- **Compilar el cliente**: más adelante, precedido de triage estático. «90% de
  confianza» es alcanzable con build reproducible, hashes y lectura dirigida;
  el 100% no existe.

## 2026-11-10 — Incidencia: discos de VM movidos al home del cliente

- `10-usuario.sh` movió `~/metin2lab` entero, incluida `vm/` con la cadena
  qcow2 de la FreeBSD. El dominio `m2-server` siguió apuntando a
  `/home/deadivine/metin2lab/vm/...` y dejó de arrancar; además `/home/metin2`
  quedó en `0700` y libvirt (usuario `libvirt-qemu`) no podía atravesarlo.
- Arreglo: la cadena (base `metin2-server.qcow2` y seis overlays hasta
  `Credenciales-ok`, más la memoria de `pre-recompilacion`) se copió a
  `/var/lib/libvirt/images/m2-server`, se rebasó a nombres relativos con
  `qemu-img rebase -u`, se actualizaron el XML del dominio y los metadatos de
  snapshots, y `/home/deadivine` volvió a `0700`. La VM arranca y responde por
  SSH.
- Lección: los discos de VM **no** van dentro de `metin2lab`. `10-usuario.sh`
  ahora aborta si encuentra `*.qcow2` o `vm/` en el laboratorio, y comprueba
  que ninguna VM de libvirt use archivos del home antes de cerrarlo.
- Xephyr: el `-fullscreen` sin salida segura queda retirado. Por defecto,
  ventana con `-no-host-grab -resizeable`; `FULLSCREEN=1` opcional y
  `16-xephyr-stop.sh` como salida.

## 2026-11-11 — C01-bis completado y runbook diario

- `10-usuario.sh` dejó `metin2` (uid 1001, grupos `render`/`video`, sin sudo),
  `/home/metin2` en `0700`, el home real en `0700` y el laboratorio con el
  cliente. Las salidas `02`–`08` confirman: sin Internet, sin DNS, el cliente
  solo conecta a `10.10.10.10`, `metin2` no lee el home real, no usa el bus de
  sesión ni el audio, y Xephyr corre dentro de `m2xephyr` (solo `lo`). El bus
  del sistema sigue como `AVISO` residual.
- GPU y render: `metin2client.exe` en la GTX 1650 con ~210 MiB; DXVK v3.1.1 por
  D3D8. La copia dorada quedó hecha: `metin2lab` es el subvolumen 322 y
  `metin2lab-golden` el 323 read-only.
- **FPS**: el HUD marca ~25 dentro de Xephyr, frente a 50/60 del mismo cliente
  en `:0` (C01b). El log muestra 1920×918 en ventana, 3 imágenes y
  `VK_PRESENT_MODE_IMMEDIATE_KHR`, con `MESA-EGL: DRI3 error` en Xephyr; en
  `:0` había 5 imágenes. Xephyr es un servidor X por software: añade copias de
  fotograma completas (juego → Xephyr → Xwayland → KWin). Las líneas `FrameSkip` también
  salían en C01b, así que no explican la caída por sí solas. La GPU no está
  saturada (37 % en `nvidia-smi`).
- **Ratón**: en juego la cámara daba saltos. Con `-no-host-grab`, cuando el
  juego captura el puntero, el cursor del host puede salir de la ventana;
  Xephyr deja de recibir movimiento y al volver salta. Se añadió
  `HOST_GRAB=1` (opt-in) para capturar el ratón mientras se juega; `Ctrl+Shift`
  lo suelta y `16-xephyr-stop.sh` sigue siendo la salida.
- **Bugs encontrados en el cierre**: `90-netns-down.sh` comprobaba
  `[ -d "$PREFIX" ]` como `deadivine`, que no puede atravesar `/home/metin2`
  (`0700`): siempre decía «no existe» y no cerraba el `wineserver`. Ahora el
  test se hace como `metin2` y, si quedan procesos en la jaula, los lista y los
  cierra antes de borrarla. `30-run-client.sh` expandía
  `"$GAME/dxvk-logs"/*_d3d*.log` en tu shell (mismo problema) y concluía «no
  hay log de DXVK» aunque DXVK sí estaba: ahora busca con `find` bajo `sudo` y
  copia el log a `~/metin2lab/logs/`.
- **Decisión**: C01-bis cerrado. El procedimiento diario queda en
  `docs/06-runbook-diario.md` (servidor → jaula → Xephyr → cliente → `90`).
  Pendiente para C02: decidir si se cierra el bus del sistema con
  `bubblewrap`, si se reduce la resolución de Xephyr por los FPS y si se
  investiga la captura del ratón como modo por defecto.

## 2026-11-12 — C02: bus del sistema enmascarado (y cámara aparcada)

- **Cámara: aparcada.** `14-xephyr-warp.sh` y su parche (`14-xephyr-warp.patch`,
  commit `d8c8526`) se aplicaron, pero el arrastre con el botón derecho siguió
  igual y **no está confirmado que el parche llegara a compilarse** (no se pidió
  la salida del build). No se revierte ni se borra nada; se retoma cuando se
  quiera, empezando por leer esa salida. Es un detalle menor frente al resto.
- **Decisión**: cerrar el bus del sistema **sin paquetes nuevos**. Se descarta
  `bubblewrap` (binario externo y SUID en algunos montajes) porque ya se usa
  `sudo` para el netns: basta un mount namespace.
- **Implementación**: `19-sin-bus.sh` (nuevo) hace
  `mount --bind /dev/null /run/dbus/system_bus_socket` y luego
  `exec sudo -u metin2`. `15-xephyr.sh` y `30-run-client.sh` lo invocan dentro
  de `sudo ip netns exec … unshare --mount --propagation private`. El montaje
  solo existe en ese namespace; al morir el proceso, desaparece. No hay cambios
  persistentes ni servicios nuevos. Además se borra `DBUS_SYSTEM_BUS_ADDRESS`
  del entorno para que nadie apunte el cliente a otra dirección.
- **Red de seguridad**: si `unshare --mount` no funciona, `15` y `30` **paran**
  en vez de arrancar con el bus visible. `SIN_BUS=1` es la única forma de
  dejarlo visible, y avisa en el log; `SIN_NETNS=1` implica lo mismo.
- **Chequeo**: `35-check-usuario.sh` ya no mira el host. Busca el proceso del
  cliente (o Xephyr) y entra con `nsenter -t PID -m` para comprobar el socket
  **dentro** de su namespace. Si no puede entrar, lo dice con `INFO` y cae al
  chequeo del host; no lo marca como `PELIGRO` por un fallo de `nsenter`.
- **Pendiente de validar en CachyOS**: que el montaje funcione
  (`OK: bus del sistema enmascarado` en el log) y que Wine siga arrancando sin
  D-Bus. Si algo se rompe, se revierte con `SIN_BUS=1` y se investiga.
- Sigue fuera de alcance: `/tmp` compartido, la cookie de `:0` en manos de
  Xephyr y un exploit de kernel. Contra lo último solo hay VM o hardware
  aparte.
