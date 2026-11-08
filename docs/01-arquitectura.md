# Arquitectura del servidor

## Procesos

El serverfile no es un solo programa: son varios procesos que se hablan por TCP.

| Proceso | Binario | Función | Escucha |
|---|---|---|---|
| `auth` | `share/bin/game` con `auth/CONFIG` | Login y lista de canales | `11000` (+ P2P `12000`) |
| `db` | `share/bin/db` con `db/conf.txt` | Único que habla con MariaDB | `127.0.0.1:15000` |
| `game99` | `share/bin/game` con `game99/CONFIG` | Servidor "principal" (`game`) | `13099` (+ P2P `14099`) |
| `channel1/first` | idem | Parte de canal | `13000` |
| `channel1/game1` | idem | Parte de canal | `13001` |
| `channel1/game2` | idem | Parte de canal | `13002` |

Cada canal son **tres** procesos (`first` + `game1` + `game2`). Con 1 canal
arrancan 6 procesos en total; con 4 canales, hasta 15. Para un laboratorio
doméstico, un canal es más que suficiente.

> El binario `game` se usa para todo (auth, game99 y canales); lo que cambia es
> el directorio de trabajo, porque cada uno lee su propio `CONFIG`.

## Directorios

```
/usr/metin2/server/
├── auth/            CONFIG, run.sh, syserr, symlinks
├── db/              conf.txt, run.sh, syserr
├── game99/          CONFIG, run.sh, syserr
├── channel1/
│   ├── first/       CONFIG, run.sh
│   ├── game1/       CONFIG, run.sh
│   └── game2/       CONFIG, run.sh
├── share/
│   ├── bin/         game, db   ← los binarios reales
│   ├── data/        mapas, scripts
│   ├── locale/      textos y quests
│   └── conf/        item_proto, mob_proto, nombres
└── start.sh         pregunta cuántos canales abrir
```

Los ejecutables de cada carpeta son **symlinks** a `../share/bin/`:

```
auth/auth     -> ../share/bin/game
db/db         -> ../share/bin/db
channel1/game1/game -> ../../share/bin/game
```

Por eso el Makefile instala en `share/bin` una vez y todos los procesos usan el
mismo binario nuevo.

## Flujo de login

```
cliente ──11000──► auth ──15000──► db ──3306──► MariaDB (127.0.0.1)
                     │
                     └─ devuelve lista de canales e IPs
cliente ──13001──► game1 (canal)  ──15000──► db
```

1. El cliente lee `pack/root/serverinfo.py` (dentro de `root.epk`) y obtiene
   `SERVER_IP`, `PORT_AUTH` (`11000`) y los puertos de canal.
2. Se conecta a `auth` y envía usuario/contraseña.
3. `auth` pide las credenciales a `db`, que consulta la base `account`.
4. Si son correctas, `auth` devuelve la lista de canales.
5. El cliente se conecta al canal (`13001`) y empieza el juego.

Consecuencia práctica: **si `db` no está arriba, `auth` acepta la conexión TCP
pero no puede autenticar**. Y si el cliente apunta a otra IP, no se ve nada en
el servidor: el paquete nunca llega.

## Configuración

No hay un `CONFIG` global. Cada proceso tiene el suyo:

- `auth/CONFIG`, `game99/CONFIG`, `channelX/*/CONFIG`: IP/puerto de escucha,
  datos de conexión al `db` y credenciales SQL.
- `db/conf.txt`: cadenas `SQL_ACCOUNT`, `SQL_COMMON`, `SQL_PLAYER`,
  `SQL_HOTBACKUP` con formato `"host base usuario contraseña 0"`, más
  `BIND_PORT = 15000`.

Todos apuntan a `127.0.0.1`; por eso restringir MariaDB a loopback no rompe
nada.

## Bases de datos

| Base | Contenido |
|---|---|
| `account` | cuentas, estado de login, contraseñas con hash `PASSWORD()` |
| `player` | personajes, ítems, guiles, inventario |
| `common` | datos compartidos entre reinos |
| `log` | registros del servidor |
| `hotbackup` | copias en caliente |

MariaDB es la **única** pieza que guarda estado. Por eso los backups son
`mysqldump` + snapshot de la VM, no copia de binarios.
