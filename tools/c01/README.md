# C01 — Cliente Wine + DXVK enjaulado

Scripts del experimento C01: cliente nativo en CachyOS con Wine + DXVK dentro
de un *network namespace*. Se ejecutan en el host, en este orden:

| Script | Qué hace | ¿Internet? |
|---|---|---|
| `00-diagnostico.sh` | Solo lectura: sesión, GPU, Vulkan, Wine, cliente, anti-cheat | no |
| `10-prefix.sh` | Crea el prefijo `win32`, quita `Z:`, copia cliente y pack | no |
| `15-dxvk.sh` | Descarga DXVK y copia `d3d9.dll`/`dxgi.dll` de 32 bits | **sí** (solo aquí) |
| `20-netns-up.sh` | Crea la jaula con una única ruta a `10.10.10.10` | no |
| `30-run-client.sh` | Lanza el cliente dentro de la jaula, como tu usuario | no |
| `35-check-isolation.sh` | Con el juego abierto: rutas, conexiones, sin Internet | no |
| `90-netns-down.sh` | Borra la jaula | no |

El prefijo y el cliente viven en `~/metin2lab/wine/`. Nada se toma de la VM
Windows: el cliente sale de `~/metin2lab/tmp4/Client/Client` y el pack
parcheado de `~/metin2lab/work/b04/`.

Reglas:

- El juego **no** se ejecuta como root.
- No se vuelve a añadir la unidad `Z:`.
- La jaula solo tiene `10.10.10.20/32` y una ruta a `10.10.10.10/32`.
- Si algo se rompe, `90-netns-down.sh` deshace la red y `rm -rf
  ~/metin2lab/wine` deshace el prefijo (el cliente original no se toca).
