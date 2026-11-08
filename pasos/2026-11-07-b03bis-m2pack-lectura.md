# B03 bis — Lectura del pack con `m2pack` corregido (CachyOS)

**Fecha:** 2026-11-07
**Máquina:** CachyOS (host).
**Riesgo:** ninguno. `m2pack` solo lee; no se escribe nada en el pack.

## Qué se corrigió

La salida de B03 dejó claro el fallo: el índice se descifraba, pero el LZO se
lanzaba en el offset equivocado. El formato real de un blob CLZO es:

```
offset 0   'MCOZ' | encrypt_size | compressed_size | real_size   (16 B)
offset 16  'MCOZ'                       <-- segundo fourcc, DENTRO del cifrado
offset 20  stream LZO de compressed_size bytes
```

`CLZObject::BeginDecompress` salta la cabecera **y** ese segundo `MCOZ`
(`m_pbIn = pvIn + sizeof(THeader) + sizeof(DWORD)`). Por eso B03 intentaba
descomprimir `MCOZ + stream` y `lzo1x_decompress_safe` devolvía `-6`.

Cambios en `tools/m2pack/m2pack.py`:

1. El LZO arranca en `descifrado[4:4 + compressed_size]` tanto en el índice
   como en los blobs de tipo 1 y 2, comprobando antes que el cuarto byte sea
   `MCOZ`.
2. `_clzo_payload` valida también `compressed_size + 4 <= encrypt_size` y
   tolera los 4 bytes extra que escribe `GetSize()`.
3. El `-n/--name` global ya no comparte destino con el `name` posicional de
   `cat`/`set` (antes `cat serverinfo.py` buscaba `serverinfo.py.eix`).

## Paso 0 — Preparación

```bash
cd ~/metin2-docs && git pull
```

## Paso 1 — Volcado único

```bash
cd ~/metin2-docs

EIX=$(find ~/metin2lab/tmp4/Client -name root.eix -print -quit)
PACK=$(dirname "$EIX")
OUT=~/metin2-docs/salidas/2026-11-07-b03bis-m2pack-lectura.txt

if [ ! -f "$PACK/root.epk" ]; then
  echo "ERROR: no encuentro root.epk junto a $EIX" >&2
  exit 1
fi

{
  echo "== 0. pack localizado =="
  echo "$PACK"
  echo
  echo "== 1. inventario =="
  ls -l "$PACK/root.eix" "$PACK/root.epk"
  sha256sum "$PACK/root.eix" "$PACK/root.epk"
  echo
  echo "== 2. primeros 64 bytes de root.eix =="
  od -A d -t x1 -N 64 "$PACK/root.eix"
  echo
  echo "== 3. primeros 64 bytes de root.epk =="
  od -A d -t x1 -N 64 "$PACK/root.epk"
  echo
  echo "== 4. m2pack info =="
  python3 ~/metin2-docs/tools/m2pack/m2pack.py -p "$PACK" info
  echo
  echo "== 5. m2pack ls (con entradas libres) =="
  python3 ~/metin2-docs/tools/m2pack/m2pack.py -p "$PACK" ls --all
  echo
  echo "== 6. serverinfo.py =="
  python3 ~/metin2-docs/tools/m2pack/m2pack.py -p "$PACK" cat serverinfo.py
  echo
  echo "== 7. m2pack verify =="
  python3 ~/metin2-docs/tools/m2pack/m2pack.py -p "$PACK" verify
  echo
  echo "== 8. versiones =="
  python3 -V
  ldconfig -p | grep -i lzo
} > "$OUT" 2>&1

wc -l "$OUT"
du -h "$OUT"
```

## Resultado esperado

- `m2pack info` debe decir `formato: ref` (o `classic`), `entradas: 90` y una
  línea `CLZO : encrypt_size=... compressed_size=... real_size=...`.
- Los primeros bytes de `root.eix` deben ser `4d 43 4f 5a` (`MCOZ`) y, en el
  offset 16, otros cuatro bytes `4d 43 4f 5a` (`MCOZ`).
- `m2pack ls` debe listar los nombres del pack; busca `serverinfo.py` y su tipo.
- `m2pack cat serverinfo.py` debe mostrar el Python con `SERVER_IP`.
- `m2pack verify` debe terminar en `RESULTADO: OK`.

Si `info` sigue fallando, el volcado de los 64 primeros bytes permite ver los
campos reales de la cabecera y ajustar sin otra ronda.

## Paso 2 — Publicar

```bash
cd ~/metin2-docs
tools/sanitize.sh salidas/2026-11-07-b03bis-m2pack-lectura.txt
git diff --stat
git add salidas/2026-11-07-b03bis-m2pack-lectura.txt
git commit -m "Salida B03 bis: lectura del pack con m2pack corregido"
git push
```

Avisa: «B03 bis subido».

## Qué hará el agente con la salida

1. Confirmar los campos reales de la cabecera CLZO del índice.
2. Leer el `serverinfo.py` real y localizar `SERVER_IP`.
3. Escribir B04: copia del pack, `m2pack set` con `10.10.10.10`, ISO mini,
   prueba en el cliente y `netsh interface portproxy reset`.

Nada de esto modifica el pack original: el `set` se hará sobre una copia.
