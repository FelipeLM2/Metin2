# Laboratorio Metin2 40250 — servidor local

Servidor de Metin2 **40250 (Mainline / TMP4)** montado en local para aprender:
leer código, compilar, entender los formatos de datos del cliente y modificar
cosas sin exponer nada a Internet.

Este repositorio es el **cuaderno del proyecto**: documentación, decisiones,
scripts propios y bitácora. **No contiene** el cliente, el serverfile ni
binarios (ver *Reglas del repo*).

## Stack

| Pieza | Detalle |
|---|---|
| Servidor | FreeBSD 13.5-RELEASE **i386**, VM KVM (i440FX, BIOS, disco SATA) |
| Base de datos | MariaDB 10.6.21, escuchando solo en `127.0.0.1:3306` |
| Compilador | `clang++-devel` 20.0.0git (i386) + `gmake` |
| Cliente | Windows 10 Home x64 en VM aparte, sin GPU (render por software) |
| Red | libvirt aislada `10.10.10.0/24`, sin NAT ni forwarding |

## Red

```
[CachyOS host]  KVM
  ├── VM FreeBSD   10.10.10.10    auth / db / game
  └── VM Windows   10.10.10.20    cliente
```

Sin puerta de enlace y sin DNS: el laboratorio no tiene salida a Internet.

## Arranque

```sh
cd /usr/metin2/server
sh start.sh      # opción 1 = un canal
sh close.sh      # parar
```

Comprobar que el servicio existe:

```sh
sockstat -4 -l | grep -E ':11000|:13001|:15000'
```

Deben aparecer `11000` (auth), `13001` (canal) y `15000` (db, en loopback).
Detalle en [`docs/01-arquitectura.md`](docs/01-arquitectura.md).

## Compilar

```sh
cd /usr/metin2/src/server/db/src   && gmake -j3
cd /usr/metin2/src/server/game/src && gmake -j3
```

El Makefile instala el binario solo (`mv` a `share/bin`). Detalle, tiempos y
marcha atrás en [`docs/03-build.md`](docs/03-build.md).

## Estado

| Fase | Contenido | Estado |
|---|---|---|
| A | Servidor propio: compilar `db`/`game`, credenciales, MySQL cerrado | ✅ |
| B | `m2pack`: leer/escribir `root.epk` y quitar el `portproxy` | 🚧 |
| C | Cliente nativo en portátil dedicado | ⏳ |
| D | Tocar código: nombres de ítems, quests, `game` | ⏳ |

Bitácora: [`docs/bitacora.md`](docs/bitacora.md).

## Flujo de trabajo

El repo es el puente entre las VMs y el agente, que no comparten portapapeles
ni carpetas.

| Carpeta | Quién escribe | Para qué |
|---|---|---|
| `docs/` | agente | documentación estable y explicaciones de conceptos |
| `pasos/` | agente | instrucciones accionables, listas para copiar en CachyOS |
| `salidas/` | usuario | volcados de comandos que el agente lee |

Ciclo:

1. El agente sube `pasos/YYYY-MM-DD-bNN-tema.md`.
2. En CachyOS: `cd ~/metin2-docs && git pull`.
3. Se copian los bloques del documento y se ejecutan en la VM indicada.
4. La salida se guarda en `salidas/` (el propio paso trae el comando).
5. `tools/sanitize.sh`, `git add`, `commit`, `push`.
6. El agente lee la salida del repo y escribe el paso siguiente.

## Reglas del repo

- Solo texto propio: documentación, scripts y notas.
- **Nunca**: cliente/serverfile, `.epk`/`.eix`, binarios, `.sql`, logs,
  `CONFIG`/`conf.txt`/`my.cnf` (contienen credenciales).
- El `.gitignore` ya los excluye. No usar `git add -f` con esos archivos.
