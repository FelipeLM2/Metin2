# C01b — Cerrar C01: DXVK de verdad y DNS cerrado

**Fecha:** 2026-11-09
**Máquina:** CachyOS (torre) y la VM FreeBSD (servidor).
**Riesgo:** bajo. No debería descargarse nada: DXVK se reutiliza de la caché
local. Se corrige la instalación y se vuelve a lanzar el mismo cliente en la
misma jaula.

## Qué pasó en C01

El usuario confirmó lo importante: la ventana apareció, **entró al juego**, el
lag desapareció («casi nativo») y el ratón va bien. La captura de FreeBSD vio
la sesión desde `10.10.10.20` (auth `11000` y canal `13000`) sin tráfico a otra
IP; el origen `.20` es la prueba de que el cliente hablaba desde la jaula.

Quedaron dos cabos sueltos:

1. **Nunca apareció el HUD de DXVK.**
2. La comprobación `35` dijo **`PELIGRO` en DNS**, aunque `curl` a Internet
   falló y la jaula no tiene ruta por defecto.

## Diagnóstico

### 1. El HUD no apareció porque DXVK no se cargó

La pista decisiva es el prefijo: Wine 11.21 con WoW64 no crea prefijos `win32`
puros, así que el prefijo real es **`win64`**. En un prefijo `win64`:

| DLL | Carpeta correcta |
|---|---|
| 32 bits (`x32`) | `drive_c/windows/syswow64` |
| 64 bits (`x64`) | `drive_c/windows/system32` |

`15-dxvk.sh` copió las DLL **de 32 bits** a `system32`. El cliente es de 32
bits, así que no las encontró y Wine cayó silenciosamente a su **`wined3d`**
(el Direct3D de Wine sobre OpenGL). Por eso:

- el juego funcionaba y usaba la GTX 1650 (por OpenGL), pero
- no había HUD de DXVK, y
- `nvidia-smi` solo demuestra que la GPU trabaja, no qué renderer se usa.

Esto coincide con el fallo conocido de `setup_dxvk.sh` en Wine 10.2+ y con la
documentación de DXVK: `x32` va a `syswow64`; solo en un prefijo puro `win32`
va a `system32`.

### 2. El `PELIGRO` de DNS era resolución de nombres, no salida a Internet

La jaula no tiene ruta por defecto y `curl https://1.1.1.1` falló. Lo que sí
funcionó fue `getent hosts example.com`: glibc no solo consulta
`/etc/resolv.conf`; también usa los módulos de `/etc/nsswitch.conf`. En
CachyOS, `nss-resolve` pregunta al **`systemd-resolved` del host por D-Bus**,
que sí tiene DNS. Vaciar `resolv.conf` no lo impide.

No había conectividad real (sin ruta no se puede llegar a la IP resuelta), pero
sí se podían filtrar nombres por esa vía. Se cierra montando en la jaula un
`nsswitch.conf` con `hosts: files`: sin módulo de red, `getent` solo mira
`/etc/hosts`.

Esto cierra la **resolución normal de nombres**, no todo D-Bus: el bus del
sistema sigue visible porque el proceso es del mismo usuario y comparte el
sistema de archivos. Esa parte es el riesgo residual que ataca C01-bis con un
usuario `metin2` aparte; no la resuelve un `network namespace`.

## Qué se ha cambiado

| Archivo | Cambio |
|---|---|
| `tools/c01/10-prefix.sh` | Prefijo `win64`/WoW64 y aviso si falta `syswow64` |
| `tools/c01/15-dxvk.sh` | `x32` → `syswow64`, `x64` → `system32`; añade `d3d8`; reutiliza la caché sin Internet |
| `tools/c01/16-verify-dxvk.sh` | **Nuevo**: arquitectura, DLLs e imports del cliente (solo lectura) |
| `tools/c01/20-netns-up.sh` | `nsswitch.conf` con `hosts: files` y prueba de DNS en la fase 3 |
| `tools/c01/30-run-client.sh` | `win64`, overrides de `d3d8`, log de DXVK y caché de shaders |
| `tools/c01/35-check-isolation.sh` | Muestra `resolv.conf`, `nsswitch.conf` y los procesos de la jaula antes de probar DNS |

## Regla de oro

Si algo imprime **`PELIGRO`**, **para y avisa**. En esta revisión, `20` y `35`
deben terminar con `OK: sin DNS` y `OK: sin salida a Internet`.

## Antes de empezar

```bash
cd ~/metin2-docs
git pull
```

La VM Windows sigue apagada y la FreeBSD encendida. No hace falta Internet: el
`.tar.gz` de DXVK ya está en `~/metin2lab/wine/dxvk/`.

---

## Fase 1 — Reinstalar DXVK en la carpeta correcta

```bash
cd ~/metin2-docs
bash tools/c01/15-dxvk.sh 2>&1 | tee salidas/2026-11-09-c01b-00-dxvk.txt
```

Debe decir `DXVK en cache: … (sin Internet)`, `prefijo: win64` y copiar
`d3d8`, `d3d9` y `dxgi` a `syswow64` (32 bits) y a `system32` (64 bits).

**PARADA** si dice que no hay caché y empieza a descargar: en esta revisión no
debe usarse Internet. Avisa y lo miramos antes de seguir.

**Comprueba a ojo:** en la salida aparecen líneas con
`windows/syswow64/d3d9.dll` y `windows/system32/d3d9.dll`, y los tamaños son
los de DXVK (varios MB), no los de Wine.

---

## Fase 2 — Verificar antes de jugar

```bash
bash tools/c01/16-verify-dxvk.sh 2>&1 | tee salidas/2026-11-09-c01b-01-verificacion.txt
```

Debe decir:

- `#arch=win64`
- `syswow64: si`
- arquitectura del cliente: `PE32 … Intel 80386` (32 bits)
- `d3d9` y `dxgi` en `syswow64` con tamaño > 1 MB
- en «DLLs que importa el cliente» puede salir vacío: es normal, el cliente
  carga `d3d8.dll` en tiempo de ejecución (el log muestra `D3D8Device`). La
  prueba real es el HUD y `metin2client_d3d9.log`
- `DXVK parece instalado en syswow64`

**PARADA** si `syswow64/d3d9.dll` no existe o mide menos de 1 MB: publica la
salida y avisa.

---

## Fase 3 — Refrescar la jaula (DNS)

```bash
bash tools/c01/20-netns-up.sh 2>&1 | tee salidas/2026-11-09-c01b-02-jaula.txt
```

Si la jaula ya existía, el script dice que no la recrea pero **sí reescribe**
`resolv.conf` y `nsswitch.conf`. Debe terminar con:

```
hosts:      files
OK: sin salida a Internet
OK: sin DNS
```

Si sigue diciendo `PELIGRO`, deshaz y vuelve a montar:

```bash
bash tools/c01/90-netns-down.sh
bash tools/c01/20-netns-up.sh 2>&1 | tee salidas/2026-11-09-c01b-02-jaula.txt
```

---

## Fase 4 — Lanzar el cliente (Terminal A)

```bash
cd ~/metin2-docs
bash tools/c01/30-run-client.sh 2>&1 | tee salidas/2026-11-09-c01b-03-cliente.txt
```

Ahora **sí** debe aparecer el HUD de DXVK en una esquina: FPS, uso de GPU y
`NVIDIA GeForce GTX 1650`. Entra en la **primera** entrada (`Metin2`), no en
`Test`, y quédate dentro unos 30 segundos.

**PARADA** si el HUD sigue sin aparecer, si dice `llvmpipe`/`HD 630`, o si el
juego se cierra. En ese caso no sigas: cierra y publica la salida.

---

## Fase 5 — Aislamiento y GPU (Terminal B)

Con el juego abierto:

```bash
cd ~/metin2-docs
bash tools/c01/35-check-isolation.sh 2>&1 | tee salidas/2026-11-09-c01b-04-aislamiento.txt
nvidia-smi 2>&1 | tee salidas/2026-11-09-c01b-05-gpu.txt
```

Debe verse:

- `ip netns pids` con procesos `wine`/`metin2client` dentro de la jaula.
- `ss` solo con conexiones a `10.10.10.10` (puertos `11000`, `13000`, `13002`…).
- `OK: sin salida a Internet` y `OK: sin DNS`.
- `nvidia-smi` con `metin2client.exe` en la GTX 1650.

La prueba definitiva de que el cliente está en la jaula sigue siendo la captura
del servidor: el origen debe ser `10.10.10.20`, no `10.10.10.1`. Si `ss` sale
vacío pero estás dentro del juego, no es grave; si `ip netns pids` también sale
vacío, para y avisa.

Opcional, para dejar constancia del renderer en el propio log:

```bash
ls -l ~/metin2lab/wine/prefix/drive_c/Games/Metin2/dxvk-logs/*_d3d*.log
```

El nombre suele ser `metin2client_d3d9.log`. Si existe, DXVK se cargó; dentro
aparecen `DXVK: v…` y `Device: NVIDIA GeForce GTX 1650`. (La ruta es de Windows
a propósito: el prefijo no tiene `Z:` y DXVK no debe depender de rutas Linux.)

---

## Fase 6 — Cerrar y publicar

1. Cierra el juego (la Terminal A vuelve sola y borra el `wineserver`).
2. Deshaz la jaula:

```bash
cd ~/metin2-docs
bash tools/c01/90-netns-down.sh
```

3. Añade el log de DXVK al final de la salida del cliente, si existe:

```bash
for f in ~/metin2lab/wine/prefix/drive_c/Games/Metin2/dxvk-logs/*_d3d*.log; do
  [ -f "$f" ] && { echo "== $f =="; cat "$f"; }
done >> salidas/2026-11-09-c01b-03-cliente.txt
```

4. Publica:

```bash
for f in salidas/2026-11-09-c01b-*.txt; do
  tools/sanitize.sh "$f"
done
git add salidas/2026-11-09-c01b-*.txt
git commit -m "Salida C01b: DXVK en syswow64 y DNS cerrado con nsswitch"
git push
```

Avisa: **«C01b subido»** y dime en el chat:

1. ¿Apareció el HUD? ¿Qué dispositivo mostró?
2. ¿`16` dijo `win64` y `d3d9` en `syswow64`?
3. ¿`35` dijo `OK` en Internet y en DNS?
4. ¿Se nota alguna diferencia de fluidez respecto a C01?
5. ¿Tuviste que recrear la jaula con `90` o bastó con `20`?

## Qué se considera éxito

- El HUD de DXVK muestra **GTX 1650** (o el log contiene `DXVK:` y el nombre
  de la GPU).
- `16` confirma `win64` y las DLLs de 32 bits en `syswow64`.
- `35` dice `OK: sin salida a Internet` y `OK: sin DNS`.
- La sesión sigue siendo solo contra `10.10.10.10`.

Si se cumple, C01 queda cerrado y pasamos a **C01-bis** (usuario Linux
`metin2`, X11/audio) y a decidir la topología definitiva en **C02**.

## Si falla

| Síntoma | Qué hacer |
|---|---|
| El HUD sigue sin aparecer | Mira si `16` ve `d3d9` en `syswow64`. Si no, vuelve a `15`. Si sí, publica `03-cliente.txt` y el log `*_d3d*.log`; DXVK está fallando al inicializar Vulkan. |
| `HUD dice llvmpipe` o `HD 630` | Fuerza la GPU: `DXVK_FILTER_DEVICE_NAME="NVIDIA GeForce GTX 1650" bash tools/c01/30-run-client.sh` |
| `Failed to initialize Vulkan` | Falta Vulkan de 32 bits: `sudo pacman -S lib32-vulkan-icd-loader lib32-nvidia-utils` |
| `PELIGRO` en DNS otra vez | La jaula no montó `nsswitch.conf`. `90-netns-down.sh`, luego `20-netns-up.sh`. Si persiste, publica `02-jaula.txt`. |
| `35` no ve procesos en la jaula | El cliente pudo nacer en la red del host por un `wineserver` viejo. Cierra todo, ejecuta `WINEPREFIX=~/metin2lab/wine/prefix WINEARCH=win64 wineserver -k` y vuelve a lanzar `30`. Si se repite, publica la salida. |
| La ventana no aparece | Comprueba `echo $DISPLAY` y `echo $XAUTHORITY`; prueba `notepad` dentro de la jaula como en C01. |
| Falla por `d3dx9_43.dll` / `msvcp140.dll` | No debería: el cliente ya arrancó en C01. Si aparece, publica el log antes de tocar `winetricks`. |

## Limpiar y repetir

```bash
bash tools/c01/90-netns-down.sh
rm -rf ~/metin2lab/wine/prefix
```

El `.tar.gz` de DXVK y el cliente original de `~/metin2lab/tmp4` no se tocan.
