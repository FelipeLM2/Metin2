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
