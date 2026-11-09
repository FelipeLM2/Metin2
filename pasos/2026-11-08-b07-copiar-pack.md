# B07 — Copiar el pack al cliente a mano (y probarlo)

**Fecha:** 2026-11-08
**Máquina:** cliente Windows 10 + una captura en CachyOS.
**Riesgo:** bajo. Se hace copia de los dos archivos actuales antes de tocarlos.

## Diagnóstico

`root.eix` en el cliente mide **2968** B: es el pack **viejo**, con
`SERVER_IP = 192.168.0.122`. El bloque de B04 se abortó antes de copiar
(seguramente no encontró la ISO o había más de un `root.eix`, y con
`$ErrorActionPreference = "Stop"` se paró sin avisar). El login que hiciste
entonces fue por el `portproxy`, que ahora ya está vacío; por eso B06 no
capturó ni un paquete: el cliente no tiene a dónde conectar.

Esta vez la copia se hace con Explorer: se ve el progreso, el aviso de
reemplazo y el tamaño final. Nada de scripts que fallan en silencio.

## Paso 1 — Comprobar que la ISO está montada

En el cliente: **Este equipo** → busca una unidad de CD llamada **B04PACK**.

Si no aparece:
1. Apaga la VM (`Stop-Computer`).
2. En `virt-manager`: detalles de la VM (**i**) → **Add Hardware**.
3. **Storage** → *Device type*: `CDROM device`, *Bus*: `SATA`,
   *Storage format*: `raw`, *Device*: selecciona
   `/home/deadivine/metin2lab/work/b04/b04-pack.iso`.
4. Arranca la VM y vuelve a mirar "Este equipo".

## Paso 2 — Localizar la carpeta del pack

En PowerShell (una línea; abre el Explorador en la carpeta correcta):

```powershell
explorer (Get-ChildItem C:\ -Filter root.eix -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).DirectoryName
```

Comprueba que dentro están `root.eix` y `root.epk` y que `root.eix` mide
**2.968 B** (si ya midiera 17.292, el paso está hecho: salta al 4).

## Paso 3 — Copia con los ojos

1. En el Escritorio crea una carpeta `pack-orig`.
2. Copia ahí `root.eix` y `root.epk` desde la carpeta del pack.
3. Renómbralos a **`root.eix.orig`** y **`root.epk.orig`** (así no se
   confunden con el pack real en las búsquedas).
4. Abre la unidad **B04PACK** en otra ventana del Explorador.
5. Arrastra `root.eix` y `root.epk` desde la ISO a la carpeta del pack.
6. Acepta **reemplazar** los dos archivos.
7. Clic derecho en el `root.eix` nuevo → **Propiedades** → debe decir
   **17.292 bytes (16,8 KB)**. El `root.epk` sigue en **520.704 bytes**.

Si el tamaño no es 17.292, la copia no se hizo: repite el arrastre y fíjate en
si sale el aviso de reemplazo.

## Paso 4 — Capturar el login

En CachyOS, terminal nueva:

```bash
cd ~/metin2-docs
OUT=salidas/2026-11-08-b07-pack-copiado.txt
ssh root@10.10.10.10 \
  "tcpdump -n -tttt -i em0 -c 80 'tcp and host 10.10.10.20'" 2>&1 | tee "$OUT"
```

Cuando salga `listening on em0`, pasa al cliente: abre el juego, entra con tu
cuenta y quédate dentro unos 10 segundos. La captura se corta sola a los 80
paquetes; si no, `Ctrl-C`.

## Paso 5 — Publicar

```bash
cd ~/metin2-docs
wc -l salidas/2026-11-08-b07-pack-copiado.txt
cat salidas/2026-11-08-b07-pack-copiado.txt
tools/sanitize.sh salidas/2026-11-08-b07-pack-copiado.txt
git add salidas/2026-11-08-b07-pack-copiado.txt
git commit -m "Salida B07: pack nuevo copiado al cliente y login capturado"
git push
```

### Resultado esperado

- Paquetes `10.10.10.20.<alto> > 10.10.10.10.11000` y luego
  `> 10.10.10.10.13000`.
- El juego entra **sin `portproxy`** (sigue vacío; no lo vuelvas a poner).

## Si falla

| Síntoma | Qué hacer |
|---|---|
| No aparece la unidad `B04PACK` | La ISO no está conectada; repite el paso 1. |
| Windows no deja reemplazar | El cliente está abierto: ciérralo y repite. |
| Sigue en 2968 | El arrastre fue a otra carpeta; mira la barra de ruta de la ventana destino. |
| Login falla pero hay SYNs al 11000 sin respuesta | El servidor no está escuchando: `ssh root@10.10.10.10 sockstat -4 -l | grep 11000`. |

## Qué hará el agente

Con la captura y el tamaño de 17.292 se cierra la Fase B y se escribe la Fase C.
