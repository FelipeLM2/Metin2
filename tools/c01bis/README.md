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
| Bus del sistema | visible | visible (riesgo residual conocido) |
| Red del juego | netns `metin2lab` | igual |

Los dos netns están separados: el juego vive en `metin2lab` (veth →
`10.10.10.10`) y Xephyr en `m2xephyr` (sin ninguna interfaz de red). Se
comunican por el socket X de `/tmp/.X11-unix/X7`, que los netns no aíslan.

Scripts, en este orden, desde `~/metin2-docs`:

| Script | Qué hace | ¿Internet? |
|---|---|---|
| `10-usuario.sh` | Crea `metin2`, mueve `~/metin2lab` a su home y protege el real | no |
| `15-xephyr.sh` | Crea `m2xephyr` y arranca Xephyr `:7` a 1080p dentro de él | no |
| `../c01/20-netns-up.sh` | Crea la jaula de red del juego (reutilizado) | no |
| `30-run-client.sh` | Lanza el cliente como `metin2` en `:7` y en `metin2lab` | no |
| `../c01/35-check-isolation.sh` | Red: rutas, conexiones, Internet, DNS | no |
| `35-check-usuario.sh` | Usuario: home, sudo, bus, audio y jaula `m2xephyr` | no |
| `80-snapshot.sh` | Convierte el laboratorio en subvolumen btrfs y crea `metin2lab-golden` | no |
| `85-reset.sh` | Restaura `metin2lab` desde la copia dorada | no |

Reglas que no cambian:

- Nada de ejecutar el cliente como root.
- Nada de `Z:` ni de carpetas compartidas.
- La jaula del juego sigue con una única ruta a `10.10.10.10/32` y sin DNS.
- Xephyr corre como el usuario real (pinta en la pantalla), pero sin red.
- Si `35-check-usuario.sh` imprime `PELIGRO`, para y avisa.
- `90-netns-down.sh` cierra Xephyr y borra las dos jaulas; no se usa a diario.
