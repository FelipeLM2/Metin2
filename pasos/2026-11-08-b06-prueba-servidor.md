# B06 — Prueba definitiva desde el servidor

**Fecha:** 2026-11-08
**Máquinas:** CachyOS (captura) y cliente Windows (dos líneas sueltas).
**Riesgo:** ninguno. Solo se observa tráfico y se limpia el redirector.

## Por qué cambiamos de método

El disco FAT de retorno falló dos veces: el archivo del cliente nunca llegó
(la salida de B05 vuelve a tener la sección del cliente vacía). No merece la
pena depurarlo.

La prueba que falta —«el cliente habla con `10.10.10.10` sin `portproxy`»— se
puede obtener **desde el servidor**, que es donde tu flujo de trabajo ya
funciona (SSH desde CachyOS). Es además una prueba más fuerte: paquetes reales
capturados en `em0`.

## Paso 0 — Preparación (CachyOS)

```bash
cd ~/metin2-docs && git pull
```

Comprueba que sigues entrando por SSH:

```bash
ssh root@10.10.10.10 "hostname; ifconfig em0 | head -3"
```

Debe responder `metin2` (o el hostname que uses) y la IP `10.10.10.10`.

## Paso 1 — Arrancar la captura (CachyOS, terminal 1)

```bash
cd ~/metin2-docs
OUT=salidas/2026-11-08-b06-prueba-servidor.txt
ssh root@10.10.10.10 \
  "tcpdump -n -tttt -i em0 -c 80 'tcp and host 10.10.10.20'" 2>&1 | tee "$OUT"
```

Se queda esperando y muestra `listening on em0, link-type EN10MB`. **No cierres
esa terminal**; sigue con el paso 2 en la VM Windows.

## Paso 2 — Cliente Windows (dos líneas)

**PowerShell como administrador.**

1. Vaciar el redirector y comprobar que quedó vacío:

```powershell
netsh interface portproxy reset; netsh interface portproxy show all
```

2. Comprobar el tamaño del pack en uso (debe ser **17292**):

```powershell
(Get-ChildItem C:\ -Filter root.eix -Recurse -ErrorAction SilentlyContinue).Length
```

Cierra el cliente si estaba abierto y **vuelve a abrirlo**: al arrancar leerá el
pack y, sin `portproxy`, solo puede conectar con `10.10.10.10`. Entra al juego y
quédate dentro unos 10 segundos.

## Paso 3 — Cerrar la captura (CachyOS)

La captura se para sola al llegar a 80 paquetes. Si se queda colgada, pulsa
`Ctrl-C` en esa terminal.

```bash
cd ~/metin2-docs
wc -l salidas/2026-11-08-b06-prueba-servidor.txt
cat salidas/2026-11-08-b06-prueba-servidor.txt
```

### Resultado esperado

- `listening on em0`.
- Una línea con `10.10.10.20.<puerto> > 10.10.10.10.11000: Flags [S]` (el
  saludo al servidor de cuentas).
- Después, tráfico hacia `10.10.10.10.13000` (el canal del juego), ya con
  `Flags [P.]` / `[.]` porque la conexión está establecida.
- Ninguna línea con otra IP de destino.

Eso, junto con el `portproxy` vacío y el pack de 17292 B, cierra la Fase B.

## Paso 4 — Publicar

```bash
cd ~/metin2-docs
tools/sanitize.sh salidas/2026-11-08-b06-prueba-servidor.txt
git add salidas/2026-11-08-b06-prueba-servidor.txt
git commit -m "Salida B06: captura en el servidor del cliente con el pack nuevo"
git push
```

Avisa: «B06 subido» y dime, con tus palabras, qué salió en las dos líneas del
paso 2 (vacío o con reglas, y el número del tamaño). Con eso no hace falta
nada más del cliente.

## Si algo falla

| Síntoma | Qué hacer |
|---|---|
| `tcpdump: em0: No such device` | `ssh root@10.10.10.10 ifconfig -l` y usa el nombre que salga. |
| `tcpdump: command not found` | `ssh root@10.10.10.10 "ls /usr/sbin/tcpdump"`; si falta, dilo y usamos `sockstat`. |
| El archivo queda vacío (solo `listening on`) | El cliente no está llegando a `10.10.10.10`: revisa el tamaño del pack y el login. |
| `netsh` dice que no se reconoce | Esa PowerShell no es de administrador. |
| La captura no llega a 80 paquetes | `Ctrl-C`; con la conexión de login ya hay evidencia. |

## Qué hará el agente con la salida

1. Confirmar los puertos 11000/13000 desde `10.10.10.20`.
2. Cerrar la Fase B en `docs/bitacora.md` y en el plan.
3. Escribir el arranque de la Fase C (portátil + adaptador USB-Ethernet).
