# B03 — Primera lectura del pack con `m2pack` (CachyOS)

**Fecha:** 2026-11-07
**Máquina:** CachyOS (host).
**Riesgo:** ninguno. `m2pack` solo lee; no se escribe nada en el pack.

## Objetivo

Probar la herramienta propia contra el `root.eix`/`root.epk` reales:

1. Confirmar que el índice se descifra y descomprime.
2. Ver la lista de los 90 archivos y en qué tipo está `serverinfo.py`.
3. Extraer `serverinfo.py` para saber qué IP lleva hoy.
4. Verificar los CRC y los tamaños de todo el pack.

Y, por si la lectura falla, recoger también `EterBase/lzo.cpp` y
`EterBase/tea.cpp` (los dos únicos archivos que faltan para ajustar la
herramienta sin otra ronda).

## Paso 0 — Preparación

```bash
cd ~/metin2-docs && git pull
```

Si `python3` no encuentra `liblzo2`:

```bash
sudo pacman -S lzo
```

## Paso 1 — Volcado único

Copia y pega el bloque completo. Localiza el pack solo, así no hay rutas
escritas a mano:

```bash
cd ~/metin2-docs

EIX=$(find ~/metin2lab/tmp4/Client -name root.eix -print -quit)
PACK=$(dirname "$EIX")
OUT=~/metin2-docs/salidas/2026-11-07-b03-m2pack-lectura.txt

if [ ! -f "$PACK/root.epk" ]; then
  echo "ERROR: no encuentro root.epk junto a $EIX" >&2
  exit 1
fi

{
  echo "== 0. pack localizado =="
  echo "$PACK"
  echo
  echo "== 1. inventario =="
  ls -l "$PACK"
  sha256sum "$PACK/root.eix" "$PACK/root.epk"
  echo
  echo "== 2. m2pack info =="
  python3 ~/metin2-docs/tools/m2pack/m2pack.py -p "$PACK" info
  echo
  echo "== 3. m2pack ls (con entradas libres) =="
  python3 ~/metin2-docs/tools/m2pack/m2pack.py -p "$PACK" ls --all
  echo
  echo "== 4. serverinfo.py =="
  python3 ~/metin2-docs/tools/m2pack/m2pack.py -p "$PACK" cat serverinfo.py
  echo
  echo "== 5. m2pack verify =="
  python3 ~/metin2-docs/tools/m2pack/m2pack.py -p "$PACK" verify
  echo
  echo "== 6. fuente LZO (por si hay que ajustar) =="
  cat ~/metin2lab/tmp4/Client/ClientVS22/source/EterBase/lzo.cpp
  echo
  echo "== 7. fuente TEA (por si hay que ajustar) =="
  cat ~/metin2lab/tmp4/Client/ClientVS22/source/EterBase/tea.cpp
  echo
  echo "== 8. claves en EterPack.cpp =="
  grep -n -A 6 "s_adwEterPackKey\|s_adwEterPackSecurityKey" \
    ~/metin2lab/tmp4/Client/ClientVS22/source/EterPack/EterPack.cpp
  echo
  echo "== 9. versiones =="
  python3 -V
  ldconfig -p | grep -i lzo
} > "$OUT" 2>&1

wc -l "$OUT"
du -h "$OUT"
```

## Resultado esperado

Lo importante está al principio del archivo:

- `m2pack info` debe decir `índice: ref` (o `classic`) y `entradas: 90`.
- `m2pack ls` debe listar nombres como `serverinfo.py`, `locale/...`, etc.
- `m2pack cat serverinfo.py` debe mostrar un Python con `SERVER_IP`,
  `PORT_AUTH` y los puertos de canal.
- `m2pack verify` debe terminar en `RESULTADO: OK`.

Si algo de esto falla, **no pasa nada**: el archivo ya trae el código de LZO y
de TEA al final, y con eso se corrige la herramienta. Lo que no hay que hacer
es tocar el pack a mano ni probar otro unpacker.

## Paso 2 — Publicar

```bash
cd ~/metin2-docs
tools/sanitize.sh salidas/2026-11-07-b03-m2pack-lectura.txt
git diff --stat
git add salidas/2026-11-07-b03-m2pack-lectura.txt
git commit -m "Salida B03: primera lectura del pack con m2pack"
git push
```

Avisa: «B03 subido».

## Qué hará el agente con la salida

1. Leer el `serverinfo.py` real y localizar la línea de `SERVER_IP`.
2. Confirmar el tipo de compresión de esa entrada.
3. Escribir el paso B04: copia del pack, `m2pack set` con la IP
   `10.10.10.10`, ISO mini, prueba en el cliente y `portproxy reset`.

Nada de esto modifica el pack original: el `set` se hará sobre una copia y la
prueba, sobre el cliente.
