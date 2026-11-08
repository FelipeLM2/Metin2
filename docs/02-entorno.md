# Entorno: máquinas, red y transferencia

## Host

| Recurso | Valor |
|---|---|
| CPU | i5-7400 (4 núcleos) |
| RAM | 12 GB |
| GPU | GTX 1650 (no se usa para las VMs del lab) |
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

## El parche temporal del cliente

El pack del cliente apunta a `127.0.0.1`. Mientras no reescribamos el pack
(Fase B), en Windows se usa un redirector de puertos:

```powershell
netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=11000 connectaddress=10.10.10.10 connectport=11000
```

Es un apaño: se elimina con `netsh interface portproxy reset` cuando el pack
lleve la IP real. Sirve además como prueba de que el cliente usa loopback.
