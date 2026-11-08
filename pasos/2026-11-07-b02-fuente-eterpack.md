# B02 — Volcar la fuente de EterPack (CachyOS)

**Fecha:** 2026-11-07
**Máquina:** CachyOS (host).
**Riesgo:** ninguno. Lectura de archivos.

## Por qué

El reconocimiento de B01 enseñó algo importante: este cliente **no** usa el
pack clásico de 40250. Usa `EterPackPolicy_CSHybridCrypt` (CryptoPP, XTEA en
modo CTR con clave/IV, y `DecryptIV` con una clave "Panama"), mientras el
índice sigue pasando por `CLZO` con `s_adwEterPackKey`.

Para escribir `m2pack` sin adivinar necesitamos el código exacto de:

- `EterPack.cpp` / `.h` — magic del índice, versión, estructura de entrada,
  claves `s_adwEterPackKey` y `s_adwEterPackSecurityKey`.
- `EterPackManager.cpp` / `.h` — cómo se abre un archivo según su `type` y si
  se comprueba el CRC.
- `EterPackCursor.*` — lectura del índice.
- `EterPackPolicy_CSHybridCrypt.*` — derivación de clave/IV.
- `CLZO` (EterBase) — cabecera `MCOZ` y orden de los campos.
- `EterBase/CRC32.cpp` — si `GetCRC32` es el CRC32 estándar.
- `EterBase/tea.h` — la variante XTEA que usa `CLZO`.

## Paso 0 — Preparación

```bash
cd ~/metin2-docs && git pull
mkdir -p salidas
```

## Paso 1 — Volcado único

Copia y pega el bloque completo. No hay que transcribir nada: escribe solo.

```bash
cd ~/metin2lab/tmp4/Client/ClientVS22
OUT=~/metin2-docs/salidas/2026-11-07-b02-fuente-eterpack.txt

{
  echo "### ESTUDIO: extracto de source/EterPack y dependencias (Fase B)"
  echo "### No forma parte del proyecto; se puede borrar tras la fase."
  echo
  echo "== 1. tamaño de los archivos =="
  wc -l source/EterPack/*.cpp source/EterPack/*.h 2>/dev/null
  echo
  echo "== 2. contenido de source/EterPack =="
  for f in source/EterPack/*.cpp source/EterPack/*.h; do
    echo "===== FILE: $f ====="
    cat "$f"
    echo
  done
  echo "== 3. CLZO =="
  grep -rln "class CLZO" source | head -5
  for f in $(grep -rln "class CLZO" source | head -5); do
    echo "===== FILE: $f ====="
    cat "$f"
    echo
  done
  echo "== 4. XTEA de EterBase =="
  ls -la source/EterBase/tea.* 2>/dev/null
  cat source/EterBase/tea.h 2>/dev/null
  echo
  echo "== 5. CRC32 =="
  cat source/EterBase/CRC32.h 2>/dev/null
  cat source/EterBase/CRC32.cpp 2>/dev/null
  echo
  echo "== 6. namespace eterpack =="
  grep -rn "namespace eterpack" -A 40 source | head -80
} > "$OUT" 2>&1

wc -l "$OUT"
du -h "$OUT"
```

Se esperan unas 3000–5000 líneas y 150–250 KB. Si sale mucho menos (por
ejemplo 100 líneas), algún `cat` falló: pega el `wc -l` y lo ajustamos.

## Paso 2 — Publicar

```bash
cd ~/metin2-docs
tools/sanitize.sh salidas/2026-11-07-b02-fuente-eterpack.txt
git add salidas/2026-11-07-b02-fuente-eterpack.txt
git commit -m "Salida B02: fuente de EterPack"
git push
```

Avisa: «B02 subido».

## Nota sobre el contenido

Este volcado es un **extracto de estudio** de código ajeno, no documentación
del proyecto. Vive en `salidas/` y se puede eliminar cuando `m2pack` esté
escrito:

```bash
git rm salidas/2026-11-07-b02-fuente-eterpack.txt
```

El agente lo necesita una sola vez para escribir la herramienta.
