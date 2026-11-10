# Entorno: máquinas, red y transferencia

## Host

| Recurso | Valor |
|---|---|
| CPU | i5-7400 (4 núcleos) |
| RAM | 12 GB |
| GPU | GTX 1650 (no se usa para las VMs del lab; sí para el cliente Wine de C01) |
| Red física | un solo puerto Ethernet, ocupado por Internet |

## VMs

| VM | Sistema | vCPU | RAM | Disco | Red |
|---|---|---|---|---|---|
| Servidor | FreeBSD 13.5 i386 | 4 | 8 GB al compilar, 4 GB normal | 46 GB (SATA, qcow2) | `10.10.10.10/24` |
| Cliente | Windows 10 Home x64 | 2 | 3 GB | 50 GB (SATA, qcow2) | `10.10.10.20/24` |

Notas de hardware virtual:

- El servidor usa **e1000**, que FreeBSD detecta como `em0`. Con `virtio` la
  imagen original no arranca bien.
- El cliente no tiene GPU: DirectX 9 va por **software (WARP)**. Se nota en
  fluidez y en el ratón, no en jugabilidad básica.
- 8 GB en FreeBSD solo para compilar; en convivencia con el cliente, 4 GB.

## Red del laboratorio

```
libvirt: red aislada "red lab"
  bridge virbr-lab  10.10.10.1/24  (solo DHCP/puente, sin <forward>)
    ├── FreeBSD  10.10.10.10  (estática)
    └── Windows  10.10.10.20  (estática, sin gateway ni DNS)
```

Decisiones deliberadas:

- **Sin `<forward>`**: la red no tiene salida a Internet. Ni la tiene el
  cliente ni puede el servidor descargar nada.
- **Sin gateway ni DNS** en el cliente: aunque algo quisiera salir, no tiene
  ruta.
- **Sin carpetas compartidas, sin portapapeles bidireccional, sin USB
  redirection**: el cliente es un `.exe` de terceros y se trata como tal.
- El servidor se administra por **SSH desde el host**, no por la consola de
  virt-manager (la consola no permite copiar/pegar).

## Transferencia de archivos

Como no hay carpetas compartidas, todo viaja por ISO:

| Qué | Cómo |
|---|---|
| Cliente completo (1,3 GB) | ISO de datos con `xorriso`, montada como CD en la VM Windows |
| Cambios en el pack (~600 KB) | **ISO mini** con solo `root.eix` + `root.epk` |

El ISO mini es la clave para iterar: montar, copiar dos archivos, expulsar,
probar. 20 segundos por ciclo en lugar de reconstruir 1,3 GB.

> C01 no usa ISO: el cliente Wine vive en la misma máquina que el host, así
> que se copia con `cp` desde `~/metin2lab/tmp4/Client/Client`. La ISO solo
> hace falta para mover archivos **entre VMs**.

```sh
# ISO del cliente completo
xorriso -as mkisofs -J -R -V M2CLIENT -o m2client.iso Client/Client

# ISO mini para probar cambios del pack
xorriso -as mkisofs -J -R -V M2PACK -o packfix.iso Client/Client/pack/root.eix Client/Client/pack/root.epk
```

## Snapshots

| Snapshot | Momento |
|---|---|
| `servidor-arranca` | Servidor arrancado y funcionando con los binarios de fábrica |
| `pre-recompilacion` | Antes de compilar `db`/`game` |
| `compilado-ok` | Tras compilar y verificar |
| `credenciales-ok` | Tras rotar contraseñas y cerrar MySQL |
| (cliente) `login-ok`, `cliente-config` | Cliente conectando y ya ajustado |

Regla: **snapshot antes de cada cambio estructural**, no después de que algo
falle.

## Las dos entradas de servidor del cliente

`serverinfo.py` trae **dos** regiones y dos nombres. En el cliente se ven como
dos servidores en la lista:

| Entrada | IP usada | Puerto | Resultado |
|---|---|---|---|
| `Metin2` (la primera) | `SERVER_IP` | `PORT_AUTH` / `PORT_1` | el servidor real |
| `Test` (la segunda) | `SERVER_IP_TEST` | `PORT_AUTH` / `PORT_1` | apunta a loopback |

Hasta B07 eso explicaba el apaño: la primera entrada llevaba
`192.168.0.122` (inalcanzable desde `10.10.10.20`) y la segunda
`127.0.0.1`, así que solo se entraba por **Test** con el redirector:

```powershell
netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=11000 connectaddress=10.10.10.10 connectport=11000
```

Desde B07 el pack lleva `SERVER_IP = "10.10.10.10"` y el redirector ya no
existe. Por eso ahora **entra la primera** y **Test falla**: su
`SERVER_IP_TEST` sigue en `127.0.0.1`, y sin `portproxy` no hay nada
escuchando ahí. Es el comportamiento esperado, no un fallo.

Si algún día molesta ver una entrada que no funciona, se puede borrar la región
2 de `serverinfo.py` y volver a empaquetar con `m2pack`; no aporta nada al
laboratorio.

## Cliente Wine (C01, en pruebas)

Para quitar el lag de la VM (WARP), C01 ejecuta el mismo cliente en CachyOS
con Wine + DXVK y lo encierra en un *network namespace*:

```
virbr-lab 10.10.10.1/24
  ├── FreeBSD  10.10.10.10        (servidor)
  └── netns "metin2lab"           (cliente Wine)
        veth-m2  10.10.10.20/32
        ruta única: 10.10.10.10/32
        sin gateway, sin DNS, sin IPv6
```

- El prefijo Wine vive en `~/metin2lab/wine/prefix`, sin la unidad `Z:`.
- Wine 11.21 con WoW64 no crea prefijos `win32` puros: el prefijo es **`win64`**
  y el cliente de 32 bits corre dentro. Sus DLLs (`d3d8`, `d3d9`, `dxgi`) van a
  `syswow64`; las de 64 bits, a `system32`. Copiarlas a `system32` hace que el
  cliente caiga a `wined3d` sin avisar (el juego va, pero sin HUD de DXVK).
- El cliente se copia a `C:\Games\Metin2` con el pack parcheado de B04.
- La VM Windows se apaga durante la prueba (misma IP `.20`), pero no se borra.
- **Sin DNS de verdad**: no basta con vaciar `resolv.conf`; `nss-resolve` puede
  preguntar al `systemd-resolved` del host por D-Bus. La jaula monta un
  `nsswitch.conf` con `hosts: files`. Sin ruta por defecto no hay conectividad,
  pero así tampoco hay resolución de nombres.
- Detalle operativo: `tools/c01/` y `pasos/2026-11-09-c01-wine-torre.md`. El
  cierre de la prueba está en `pasos/2026-11-09-c01b-cierre-dxvk-dns.md`.
