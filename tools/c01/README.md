# C01 — Cliente Wine + DXVK enjaulado

Scripts del experimento C01: cliente nativo en CachyOS con Wine + DXVK dentro
de un *network namespace*. Se ejecutan en el host, en este orden:

| Script | Qué hace | ¿Internet? |
|---|---|---|
| `00-diagnostico.sh` | Solo lectura: sesión, GPU, Vulkan, Wine, cliente, anti-cheat | no |
| `10-prefix.sh` | Crea el prefijo `win64`/WoW64, quita `Z:`, copia cliente y pack | no |
| `15-dxvk.sh` | Instala DXVK: `x32` en `syswow64`, `x64` en `system32` | solo la primera vez |
| `16-verify-dxvk.sh` | Solo lectura: arquitectura, DLLs instaladas e imports del cliente | no |
| `20-netns-up.sh` | Crea la jaula con una única ruta a `10.10.10.10` y sin DNS | no |
| `30-run-client.sh` | Lanza el cliente dentro de la jaula, como tu usuario | no |
| `35-check-isolation.sh` | Con el juego abierto: rutas, conexiones, sin Internet ni DNS | no |
| `90-netns-down.sh` | Borra la jaula | no |

El prefijo y el cliente viven en `~/metin2lab/wine/`. Nada se toma de la VM
Windows: el cliente sale de `~/metin2lab/tmp4/Client/Client` y el pack
parcheado de `~/metin2lab/work/b04/`.

Detalles que han costado un intento:

- **Prefijo `win64`**: Wine 10+ con WoW64 ya no crea prefijos `win32` puros. El
  cliente es de 32 bits y corre igual dentro del prefijo de 64 bits.
- **DLLs de 32 bits en `syswow64`**, no en `system32`. Si van a `system32`, el
  cliente de 32 bits no las ve y Wine cae a `wined3d`: el juego funciona, pero
  no hay HUD de DXVK. Para un prefijo puro `win32` sí irían a `system32`.
- **Sin DNS de verdad**: vaciar `resolv.conf` no basta; `nss-resolve` sigue
  preguntando al `systemd-resolved` del host por D-Bus. La jaula monta un
  `nsswitch.conf` con `hosts: files`.

Reglas:

- El juego **no** se ejecuta como root.
- No se vuelve a añadir la unidad `Z:`.
- La jaula solo tiene `10.10.10.20/32` y una ruta a `10.10.10.10/32`.
- Si algo se rompe, `90-netns-down.sh` deshace la red y `rm -rf
  ~/metin2lab/wine` deshace el prefijo (el cliente original no se toca).
