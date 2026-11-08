# B01 — Reconocimiento de EterPack (CachyOS)

**Fecha:** 2026-11-07
**Máquina:** CachyOS (host). No tocar la VM FreeBSD.
**Riesgo:** ninguno. Todo es lectura; no se modifica ni un byte del cliente.

## Objetivo

Localizar en la fuente del cliente (`ClientVS22`) cuatro cosas que necesitamos
con exactitud para escribir `m2pack`:

1. La función **XTEA** tal como la implementa este cliente (orden de rondas,
   delta, suma: varía entre revisiones).
2. Las **claves** XTEA del índice y de los datos.
3. La **estructura de entrada** del índice (nombre, tamaños, posición, tipo).
4. Si el cliente **verifica los CRC** al abrir un archivo del pack.

## Paso 0 — Preparación (una sola vez)

Si aún no tienes el repo clonado en CachyOS:

```bash
git clone https://github.com/FelipeLM2/Metin2.git ~/metin2-docs
cd ~/metin2-docs
git config user.name "FelipeLM2"
git config user.email "353907325+FelipeLM2@users.noreply.github.com"
```

Para poder hacer `push` desde CachyOS, autentica una vez (elige **una**):

```bash
# opción A: GitHub CLI (recomendada)
sudo pacman -S github-cli
gh auth login          # GitHub.com -> HTTPS -> login por navegador

# opción B: token fine-grained en https://github.com/settings/tokens
#   permiso: Contents = Read and write, solo este repo, caducidad 30 dias
git config credential.helper store   # lo guarda en ~/.git-credentials (texto plano)
```

Y actualiza:

```bash
cd ~/metin2-docs && git pull
mkdir -p salidas
```

## Paso 1 — Volcado (un solo bloque)

Copia y pega esto tal cual. Guarda todo en `salidas/` para que el agente lo
lea sin que tengas que transcribir nada:

```bash
cd ~/metin2lab/tmp4/Client/ClientVS22

{
  echo "== 1. estructura =="
  ls -1
  echo
  echo "== 2. archivos eterpack =="
  find . -maxdepth 4 -iname '*eterpack*'
  echo
  echo "== 3. herramientas =="
  python3 -V
  ldconfig -p | grep -i lzo || echo "liblzo2 NO encontrada"
  which xorriso git
  echo
  echo "== 4. xtea =="
  grep -rn -i "xtea" --include='*.cpp' --include='*.h' . | head -80
  echo
  echo "== 5. magic y estructuras =="
  grep -rn "MCOZ\|EPKD" --include='*.cpp' --include='*.h' . | head -40
  echo
  echo "== 6. crc =="
  grep -rn "crc32\|GetCRC32" --include='*.cpp' --include='*.h' . | head -40
} > ~/metin2-docs/salidas/2026-11-07-b01-recon-eterpack.txt 2>&1

wc -l ~/metin2-docs/salidas/2026-11-07-b01-recon-eterpack.txt
```

Resultado esperado: entre 100 y 500 líneas. Si `liblzo2 NO encontrada`, se
instala luego (`sudo pacman -S lzo`); no impide este paso.

## Paso 2 — Si el volcado sale vacío o muy corto

Significa que esas cadenas no están en el código del cliente, sino en una
librería ya compilada. En ese caso ejecuta también:

```bash
cd ~/metin2lab/tmp4/Client/Client
find . -maxdepth 2 -iname '*.dll' -o -maxdepth 2 -iname '*.exe' | head -20
grep -rn -i "eterpack\|packmanager" ~/metin2lab/tmp4/Client/ClientVS22 --include='*.cpp' | head -40
```

Y añade la salida al mismo archivo:

```bash
{ find . -maxdepth 2 \( -iname '*.dll' -o -iname '*.exe' \) | head -20
  grep -rn -i "eterpack\|packmanager" ~/metin2lab/tmp4/Client/ClientVS22 --include='*.cpp' | head -40
} >> ~/metin2-docs/salidas/2026-11-07-b01-recon-eterpack.txt 2>&1
```

## Paso 3 — Publicar la salida

```bash
cd ~/metin2-docs
tools/sanitize.sh salidas/2026-11-07-b01-recon-eterpack.txt
git diff --stat
git add salidas/2026-11-07-b01-recon-eterpack.txt
git commit -m "Salida B01: recon EterPack"
git push
```

Después, avisa: «B01 subido». El agente lo lee del repo y escribe `B02`
(probablemente «diseño de m2pack» ya con las claves y la función exactas).

## Qué busca el agente en la salida

| Señal | Dónde suele estar |
|---|---|
| `XTEA_Decrypt` / `xtea_decrypt` | `EterPack.cpp`, `EterPackManager.cpp` |
| tablas de 4 `DWORD` (`c_aucXTEAKey`, `*KEY`) | `EterPack.h` o `CryptLib` |
| `MCOZ` / `EPKD` | cabeceras del pack |
| `SEterPackFileInfo` / struct de 192 bytes | `EterPackManager.h` |
| `GetCRC32` / comparación de CRC | decide si hay que recalcularlos |

Si algo no aparece, no es problema: con las claves en una cabecera basta, y el
resto se puede deducir del propio archivo (ya conocemos sus cabeceras).
