# Modelo de seguridad y confianza

## La pregunta

¿Se puede saber con certeza que el cliente y el servidor no tienen malware?

**No.** No existe un método que *demuestre* que un binario cerrado de 1,3 GB
está limpio: ni antivirus, ni VirusTotal, ni analizar imports prueban la
ausencia de una puerta trasera. Lo que sí se puede hacer es bajar la confianza
depositada y acotar el daño.

## Escalera de confianza

| Nivel | Qué aporta | Coste | Riesgo residual |
|---|---|---|---|
| 0. Aislamiento | Nada se puede exfiltrar ni propagar | ya hecho | el binario sigue siendo desconocido |
| 1. Triage estático (imports, strings, entropía) | descarta lo obvio | ~1 h | ofuscación, dropper remoto |
| 2. Vigilancia de red (solo habla con `10.10.10.10`) | detecta C2 al ejecutar | ~30 min | payload dormido sin red |
| 3. Compilar el cliente desde las fuentes incluidas | sustituye el binario ajeno por el propio | 1–2 días | toolchain y libs precompiladas |
| 4. Auditar fuentes y `extern` | confianza casi total en el código | semanas | assets y parsers |

## Lo que se demostró en el servidor

El servidor está en **nivel 3**, y con una particularidad excelente: el build
es **reproducible**. Compilar las fuentes incluidas con el toolchain incluido
produce bytes idénticos a los binarios distribuidos.

Eso demuestra que **los binarios distribuidos corresponden a las fuentes
incluidas** — se descarta la vía "fuente limpia + ejecutable troyanizado".
No demuestra que las fuentes sean benignas; eso se ataca leyendo código, y no
es viable a mano en un árbol de este tamaño. En la práctica se hace con
búsquedas dirigidas: `system(`, `popen`, `exec`, sockets a IPs externas,
`dlopen`, cadenas en base64.

## Contención: la parte que de verdad protege

Un cliente malicioso solo es peligroso si tiene **a dónde enviar** y **qué
robar**. En este montaje:

- Red aislada sin forwarding: no hay ruta a Internet ni a la LAN doméstica.
- Cero datos personales, cuentas, correo o nube en el entorno del cliente: la
  VM no los tenía; en C01-bis el usuario `metin2` no puede leer el home real
  (solo ve su propio home, `/tmp` y el display `:7`, ya documentados).
- Sin carpetas compartidas ni USB redirection. En C01-bis no se pasa audio y
  Xephyr mantiene su portapapeles separado del host por defecto (no hay puente).
- Los discos de las VMs no viven en el home del cliente: la cadena qcow2 de la
  FreeBSD está en `/var/lib/libvirt/images/m2-server`, propiedad de
  `libvirt-qemu`. Así `metin2` no puede leerla, borrarla ni sustituirla, y
  libvirt no depende de los permisos de `/home`.
- Snapshots para volver a cero: la VM antes; ahora el subvolumen btrfs dorado
  del cliente, más los snapshots de la FreeBSD.

Aunque el `.exe` fuese un troyano, no tiene salida mientras no explote el
kernel o Xephyr. Regla mental:
**"limpio" no se demuestra; "sin consecuencias" se diseña.**

## Endurecimiento aplicado

| Elemento | Antes | Ahora |
|---|---|---|
| root de FreeBSD | clave de fábrica | rotada |
| root de MariaDB | clave de fábrica | rotada |
| `admin` del juego | clave de fábrica | rotada (`PASSWORD()`) |
| `bind-address` de MariaDB | `*` (0.0.0.0:3306) | `127.0.0.1` |
| `root@%` en MySQL | existía con la clave vieja | eliminado |
| Cuentas anónimas (`''@localhost`, `''@metin2.code`) | existían | eliminadas |

Hallazgo relevante: el informe inicial daba por hecho que MariaDB solo
escuchaba en loopback. No era cierto: `bind-address = *` y `root@%` con la
contraseña de fábrica. Se verificó conectando desde la IP del laboratorio y
obteniendo respuesta; después del cambio, la conexión ya no llega al puerto.

## Pendiente (deliberado)

- Usuario SQL `metin2` con contraseña de fábrica. Está repetido en las
  configuraciones de auth/canales/`db/conf.txt`; se rota en un paso aparte,
  con búsqueda `grep -rl` y prueba de login después.
- `ADMINPAGE_PASSWORD` del auth (la página solo escucha en `127.0.0.1`).
- Cuenta de juego `test`: revisar si tiene personajes antes de borrarla.

## El cliente sigue en nivel 0

El cliente Windows no se ha recompilado. Su aislamiento (red sin salida, sin
datos) es lo que lo hace seguro de usar, no un análisis del binario. La vía
para subir de nivel es compilar `ClientVS22` y comparar comportamiento, y eso
es Fase D.

## C01: el cliente nativo enjaulado

Para quitar el lag de la VM (render por software, WARP) sin renunciar a la
contención, C01 mueve el cliente a CachyOS con Wine + DXVK y lo mete en un
*network namespace*. La jaula es del propio kernel (`ip netns`), no un binario
SUID de terceros.

| Aspecto | Antes (VM Windows) | C01 (Wine en el host) |
|---|---|---|
| Red | bridge `virbr-lab` sin forwarding | netns + `veth`: solo `10.10.10.20/32` y ruta a `10.10.10.10/32`, sin gateway ni DNS |
| Disco | disco virtual aislado | prefijo Wine aparte, sin la unidad `Z:` (Wine no ve `/`) |
| Ejecución | usuario de Windows | usuario Linux normal, **nunca root** |
| GPU | WARP (software) | GTX 1650 vía Vulkan/DXVK |

Lo que la jaula **sí** garantiza: aunque el `.exe` sea un troyano, no tiene
interfaz ni ruta hacia Internet; solo puede hablar con `10.10.10.10`, que a su
vez está en una red sin salida. Lo que **no** garantiza: aislamiento total del
sistema de archivos (el proceso es del mismo usuario) ni de X11 (puede inyectar
teclado o leer el portapapeles). Por eso, si C01 funciona, el endurecimiento
siguiente es un usuario Linux `metin2` con su propio `/home`, y valorar Xephyr.

**C01-bis** da ese paso: el cliente pasa a un usuario `metin2` sin sudo (solo
grupos `render`/`video` para la GPU), con `/home` propio (0700) y un **Xephyr**
(`:7`) que solo muestra sus ventanas, así no ve el escritorio real ni el
portapapeles. No se le pasa audio ni bus de sesión (sus sockets son 0600 del
usuario real). Además, Xephyr corre dentro de un netns vacío (`m2xephyr`, solo
`lo`, sin rutas ni DNS): si lo comprometen, el código no tiene red. El juego
sigue en `metin2lab` y se conecta a `:7` por el socket Unix
`/tmp/.X11-unix/X7`, que los netns no aíslan.

El **bus del sistema** (`/run/dbus/system_bus_socket`, 0666) era la última vía
conocida hacia el host: cualquier proceso del cliente podía hablar con systemd,
logind o NetworkManager. **C02 lo cierra sin paquetes nuevos:** `15-xephyr.sh` y
`30-run-client.sh` se envuelven en `unshare --mount --propagation private` y
`19-sin-bus.sh` hace `mount --bind /dev/null` sobre ese socket dentro del
namespace. El montaje vive solo en ese proceso y desaparece al terminar; el host
no cambia y no hace falta `bubblewrap` ni un binario SUID. Además se borra
`DBUS_SYSTEM_BUS_ADDRESS` del entorno, para que nadie pueda apuntar el cliente a
otra dirección. `35-check-usuario.sh` ya no comprueba el host: entra con
`nsenter` en el mount namespace del cliente (o de Xephyr) y mira ahí, que es
donde importa.

Siguen fuera de alcance `/tmp` compartido y el hecho de que Xephyr corre como el
usuario real, con la cookie de `:0` (sin red, pero con acceso a sus archivos y a
su sesión X). Xephyr no comparte el portapapeles con `:0` por defecto; si algún
día se añade un sincronizador, se abre ese puente.

**Matiz aprendido en la primera ejecución (C01):** vaciar `resolv.conf` no
desactiva la resolución de nombres si `nsswitch.conf` incluye `nss-resolve`:
ese módulo pregunta al `systemd-resolved` **del host** por D-Bus y sí tiene
DNS. La comprobación `35` lo detectó como `PELIGRO`. No era una fuga de
conectividad —la jaula no tiene ruta por defecto y `curl` a Internet falla—,
pero sí permitía filtrar nombres. Se cierra montando dentro de la jaula un
`nsswitch.conf` con `hosts: files`, así `getent` solo mira `/etc/hosts`. Lección:
**una jaula de red se comprueba con conectividad y con resolución de nombres**;
lo primero no implica lo segundo.

El binario sigue en **nivel 0**: no se ha analizado. La diferencia es que ahora
el daño posible está acotado por la jaula, no por la buena fe del `.exe`.

## Copias doradas del cliente (btrfs)

El progreso del juego (personajes, cuentas, inventario) vive en MariaDB dentro
de la FreeBSD. El cliente solo guarda el prefijo de Wine, DXVK y su
configuración. Por eso una copia del cliente es una **instalación
conocida-buena**, no una partida guardada.

- `tools/c01bis/80-snapshot.sh` convierte `/home/metin2/metin2lab` en
  subvolumen btrfs (si no lo es) y crea `metin2lab-golden` en modo read-only.
  La conversión conserva la copia anterior en `metin2lab.pre-subvol`.
- `tools/c01bis/85-reset.sh` aparta el laboratorio actual en
  `metin2lab.roto-<fecha>` y crea uno nuevo desde `metin2lab-golden`. No borra
  nada de forma silenciosa.

Esto no sustituye a los snapshots de la VM FreeBSD: son cosas distintas. El
cliente se puede reconstruir; la base de datos no.
