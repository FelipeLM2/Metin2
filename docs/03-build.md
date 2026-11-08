# Compilación

## Toolchain

| Pieza | Versión |
|---|---|
| FreeBSD | 13.5-RELEASE **i386** (solo 32 bits) |
| Compilador | `clang++-devel` 20.0.0git, target `i386-portbld-freebsd13.4` |
| Make | `gmake` (GNU make; los Makefiles usan `$(shell ...)`) |
| Python | 2.7 (quests) y 3.11 (scripts propios) |

Flags del `game` (`src/server/game/src/Makefile`):

```
-m32 -O2 -pipe -std=c++23 -fexceptions -D_THREAD_SAFE -DNDEBUG
-mtune=i686 -fstack-protector-all -g -Wall -w
```

## Cómo compilar

```sh
sh                       # el shell de root es csh/tcsh; pasar a POSIX
cd /usr/metin2/src/server/db/src
nohup gmake -j3 > /root/build_db.log 2>&1 &
```

Vigilar sin matar el build (`Ctrl+C` sale del `tail`):

```sh
pgrep -fl gmake
tail -n 20 /root/build_db.log
```

Luego lo mismo con el `game`:

```sh
cd /usr/metin2/src/server/game/src
nohup gmake -j3 > /root/build_game.log 2>&1 &
```

Tiempos observados: `db` ~2 min, `game` ~30 min con `-j3` y 8 GB de RAM.

## Detalles que sorprenden

**El Makefile instala solo.** El target es `../game` (`BINDIR = ..`), y la
última orden de la receta es:

```make
@mv $(TARGET) $(GAMEDIR)
```

con `GAMEDIR = /usr/metin2/server/share/bin`. No hay paso de instalación
manual; por eso `src/server/game/game` no existe después de compilar.

**Las librerías no se recompilan.** `libthecore`, `libgame`, `libsql`,
`libpoly`, `liblua`, `libserverkey`, `libcryptopp` y DevIL ya vienen como
`.a` en `lib/` y `extern/lib/`. Con eso basta.

**El build es reproducible.** Compilar `db` y `game` con este toolchain produce
un SHA256 **idéntico** al de los binarios distribuidos por TMP4:

```
db    b172a44c…6ba88
game  7e300a0e…9253a
```

Mismo compilador, mismos flags (incluido `-g` con las mismas rutas absolutas),
mismas librerías, mismo código → mismo binario. Consecuencias:

- Los binarios de TMP4 son el build de las fuentes incluidas: no hay
  modificación oculta en el ejecutable.
- El código no usa `__DATE__`/`__TIME__` (si no, el hash cambiaría).
- Cuando modifiquemos una línea, el hash cambiará y sabremos que ejecutamos
  nuestro código.

## RAM y jobs

- 8 GB para compilar; 4 GB para convivir con la VM del cliente (3 GB).
- `-j3` con 4 vCPU. `-j4`/`-j9` compiten con el host y con MariaDB.
- Si el linker muere sin mensaje (`Killed`), es RAM: bajar a `-j2`.

## Marcha atrás

Antes de compilar, copia de los binarios originales:

```sh
cp -p /usr/metin2/server/share/bin/game /root/backup/game.orig
cp -p /usr/metin2/server/share/bin/db   /root/backup/db.orig
sha256 /root/backup/*.orig
```

Si el binario nuevo falla:

```sh
cd /usr/metin2/server && sh close.sh
cp -p /root/backup/game.orig /usr/metin2/server/share/bin/game
cp -p /root/backup/db.orig   /usr/metin2/server/share/bin/db
```

Y si el desastre es mayor: snapshot de la VM.

## Saltarse el `install.sh` del paquete

El paquete trae un `install.sh` que reinstala cosas y puede pisar la
configuración actual. En este proyecto **no se usa**: el servidor ya está
instalado y lo único que se recompila son `db` y `game`.
