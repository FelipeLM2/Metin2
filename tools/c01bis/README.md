# C01-bis — Cliente con usuario Linux aparte

C01 dejó el cliente funcionando en CachyOS (Wine + DXVK, jaula de red). C01-bis
quita el último privilegio del `.exe`: deja de correr como el usuario real.

| Aspecto | C01/C01b | C01-bis |
|---|---|---|
| Usuario | `deadivine` | `metin2` (sin sudo; solo `render`/`video` para la GPU) |
| Home | el real | `/home/metin2` (0700) |
| X11 | display `:0` (el escritorio) | Xephyr `:7` (X anidado, solo su ventana) |
| Audio | el del usuario | sin audio (a propósito) |
| Bus de sesión | no se pasa | inaccesible (socket 0600) |
| Bus del sistema | visible | visible (riesgo residual conocido) |
| Red | netns `metin2lab` | igual |

Scripts, en este orden, desde `~/metin2-docs`:

| Script | Qué hace | ¿Internet? |
|---|---|---|
| `10-usuario.sh` | Crea `metin2`, mueve `~/metin2lab` a su home y protege el real | no |
| `15-xephyr.sh` | Arranca Xephyr en `:7` con `-ac` (solo ese display) | no |
| `../c01/20-netns-up.sh` | Crea la jaula de red (reutilizado) | no |
| `30-run-client.sh` | Lanza el cliente como `metin2` en `:7` y en la jaula | no |
| `../c01/35-check-isolation.sh` | Red: rutas, conexiones, Internet, DNS | no |
| `35-check-usuario.sh` | Usuario: home, sudo, bus de sesión, audio, bus del sistema | no |

Reglas que no cambian:

- Nada de ejecutar el cliente como root.
- Nada de `Z:` ni de carpetas compartidas.
- La jaula sigue con una única ruta a `10.10.10.10/32` y sin DNS.
- Si `35-check-usuario.sh` imprime `PELIGRO`, para y avisa.
