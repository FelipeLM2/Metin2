# EterPack: cómo está hecho `root.eix` / `root.epk`

Documento de estudio. Todo lo que hay aquí sale de
`ClientVS22/source/EterPack` (volcado en
`salidas/2026-11-07-b02-fuente-eterpack.txt`), no de suposiciones.

## Idea general

El cliente no lee los archivos del juego del disco: los lee de un **pack**. Un
pack son dos archivos que se usan juntos:

| Archivo | Para qué |
|---|---|
| `root.eix` | **índice**: qué archivos hay, dónde empieza cada uno y cómo está guardado |
| `root.epk` | **datos**: los blobs, uno detrás de otro |

El índice es pequeño (KB); los datos pueden ser cientos de MB. El cliente abre
el índice una vez, se queda con la lista en memoria y luego, cuando pide
`serverinfo.py`, busca su entrada y lee solo ese trozo del `.epk`.

## El nombre del archivo es un CRC

Para buscar rápido, el índice no compara cadenas: compara un **CRC32 del
nombre normalizado**.

```cpp
inline void inlineConvertPackFilename(char* name) {
    // '\\' -> '/', y todo a minúsculas
}
```

Es decir:

```
"Pack/Root/ServerInfo.py"  ->  "pack/root/serverinfo.py"  ->  CRC32
```

Consecuencia práctica: si cambias el nombre de un archivo dentro del pack,
tienes que recalcular `filename_crc`. `m2pack` lo hace.

## Cómo se guarda cada archivo

Cada entrada del índice apunta a un **blob** dentro del `.epk`. El blob puede
estar en cinco formas, según `compressed_type`:

| Tipo | Nombre | Qué lleva |
|---|---|---|
| 0 | `none` | los bytes tal cual |
| 1 | `compress` | LZO |
| 2 | `security` | LZO + cifrado TEA |
| 3 | `panama` | cifrado Panama (CryptoPP) |
| 4 | `hybrid` | Camellia/Twofish/XTEA en modo CTR |
| 5 | `hybrid+sdb` | como 4, más un bloque extra |

Los tipos 1 y 2 comparten una cabecera de 16 bytes, `CLZObject::THeader`:

```
offset  tamaño  campo
0       4       dwFourCC          'MCOZ'
4       4       dwEncryptSize     bytes cifrados (0 si no hay cifrado)
8       4       dwCompressedSize  bytes que ocupa el LZO
12      4       dwRealSize        bytes que ocupa el archivo original
16      4       'MCOZ'            segundo fourcc, dentro del área cifrada
20      ...     stream LZO
```

Ese **segundo `MCOZ`** es fácil de pasar por alto y es la causa del error más
típico al escribir un lector propio: el stream LZO no empieza en el offset 16,
sino en el **20**. Lo pone `CLZObject::Compress` y lo salta `BeginDecompress`
(`m_pbIn = pvIn + sizeof(THeader) + sizeof(DWORD)`).

Leer un tipo 1 es: `payload[4:4+dwCompressedSize]` → `lzo1x_decompress` →
`dwRealSize` bytes.

Leer un tipo 2 es: `payload[:dwEncryptSize]` → descifrar TEA → comprobar que
empieza por `MCOZ` → `descifrado[4:4+dwCompressedSize]` → `lzo1x_decompress`.

Ese orden importa: primero se comprime y luego se cifra; para leer, al revés.

Al cifrar, `CLZObject::Encrypt` llama a `tea_encrypt` **desde el offset 16** y
con `dwCompressedSize + 19` bytes; `tea_encrypt` redondea a múltiplo de 8 y
devuelve ese tamaño como `dwEncryptSize`. El fuente de `ClientVS22` calcula
`GetSize() = 16 + 4 + dwEncryptSize`, pero el `root.eix` real de TMP4 mide
**2968 = 16 + 2952** (sin el `+4` extra). La diferencia no afecta a la lectura:
`m2pack` usa los campos de la cabecera y nunca el tamaño del archivo.

El `+4` del fuente cuenta el `MCOZ` interno, que también va cifrado; por eso el
stream LZO está en el offset 20 aunque el área cifrada empiece en el 16.

## El índice

### Forma plana

```
offset  tamaño  campo
0       4       'EPKD'
4       4       versión = 2
8       4       número de entradas (int32)
12      192×N   entradas
```

### Forma cifrada

El archivo entero es un blob tipo 2 con la clave `s_adwEterPackKey`:

```
'MCOZ' | encrypt | compressed | real | 'MCOZ' | TEA(LZO(índice plano))
```

El índice plano va precedido del `MCOZ` interno, igual que cualquier otro blob;
TEA cubre desde ese `MCOZ` interno hasta completar `encrypt` bytes.

El cliente acepta **las dos**: si el primer DWORD es `EPKD`, lo lee directo; si
es `MCOZ`, lo descomprime y descifra. Esto es lo que permite que `m2pack`
escriba el índice en claro sin tocar el cifrado.

Comprobado en B04/B07 (2026-11-08): un `set` que reescribe el `.eix` en claro
(2968 → 17 292 B) lo acepta el cliente de TMP4 sin problema y el juego entra
normal. No hace falta reproducir TEA para escribir.

### La entrada: 192 bytes

`SEterPackIndex` con `#pragma pack(4)`:

| Offset | Bytes | Campo | Notas |
|---:|---:|---|---|
| 0 | 4 | `id` | índice dentro del propio array |
| 4 | 161 | `filename` | ASCII, acabado en `\0` |
| 165 | 3 | *padding* | por `pack(4)` |
| 168 | 4 | `filename_crc` | CRC32 del nombre normalizado; **0 = entrada libre** |
| 172 | 4 | tamaño del blob | bytes reales que ocupa el blob (sin relleno) |
| 176 | 4 | hueco | espacio reservado en el `.epk` (múltiplo de 256) |
| 180 | 4 | `data_crc` | CRC32 del blob almacenado |
| 184 | 4 | `data_position` | offset absoluto dentro del `.epk` |
| 188 | 1 | `compressed_type` | 0–5 |
| 189 | 3 | *padding* | hasta 192 |

Los 161 bytes del nombre (160 + `\0`) más el padding son la razón de que una
entrada mida 192 y no 186. Por eso `17292 = 12 + 90 × 192`: el `root.eix`
original tiene 90 entradas.

**Ojo con el orden de los dos tamaños.** El fuente de `ClientVS22` declara en
`SEterPackIndex` primero `real_data_size` (hueco) y después `data_size` (blob).
Pero el pack real de TMP4 los guarda al revés: en `serverinfo.py`, el campo del
offset 172 vale **636** (blob real = `16 + 4 + compressed_size`) y el del 176
vale **768** (hueco redondeado a 256). Por eso `m2pack` no asume el orden: usa
el menor como tamaño real y el mayor como hueco.

El hueco se reserva redondeando a 256 bytes y se rellena con ceros. Ese hueco
es lo que permite reemplazar un archivo por otro algo más grande sin mover
nada.

## Las claves

En `EterPack.cpp`:

```cpp
static DWORD s_adwEterPackKey[] = {
    45129401, 92367215, 681285731, 1710201,
};

static DWORD s_adwEterPackSecurityKey[] = {
    78952482, 527348324, 1632942, 486274726,
};
```

- La primera cifra el **índice** (`EncryptIndexFile`).
- La segunda cifra los archivos de tipo 2 (`COMPRESSED_TYPE_SECURITY`).

Son claves de 128 bits (cuatro `DWORD`), públicas en el código: no aportan
seguridad real, solo evitan que el pack se abra con un `unzip`.

## El cifrado

`EterBase/tea.cpp` implementa TEA/XTEA con 32 rondas y `delta = 0x9E3779B9`.
La variante exacta es la de la referencia `xtea.ps`:

```
y += (((z<<4) ^ (z>>5)) + z) ^ (sum + key[ sum       & 3])
sum += delta
z += (((y<<4) ^ (y>>5)) + y) ^ (sum + key[(sum>>11) & 3])
```

Es fácil equivocarse con el índice de la clave (`sum & 3` frente a
`ronda & 3`): son variantes distintas y producen basura si se confunden. Por
eso `m2pack` prueba dos variantes y acepta la que produce un índice que empieza
por `EPKD` con versión 2.

## El CRC

`EterBase/CRC32.cpp` usa la tabla estándar de CRC-32 (la misma de zlib/PKZIP),
con `crc = 0xFFFFFFFF` al empezar y XOR final. En Python:

```python
zlib.crc32(data) & 0xFFFFFFFF
```

El cliente solo comprueba `data_crc` para los tipos 2 y 3 (los "seguros"). Un
archivo de tipo 0 o 1 con CRC mal puesto se lee igual; aun así `m2pack` lo
calcula bien siempre.

## Estrategia de `m2pack`

Leer es obligatorio; escribir, lo mínimo:

1. **Leer**: descifrar el índice (o leerlo plano), listar entradas y extraer
   archivos de tipo 0/1/2.
2. **Escribir**: reemplazar un archivo con **tipo 1** (LZO, como el original)
   o con tipo 0 (crudo), en su hueco si cabe, y reescribir el `.eix` en forma
   **plana**.

Escribir tipo 1 solo necesita `lzo1x_1_compress` (la misma función que usa
`CLZObject`), no TEA: la clave solo cifra el índice y los archivos de tipo 2.
Elegir tipo 1 mantiene el pack igual que el original y hace que el cliente
ignore el relleno del hueco, porque el tamaño lo manda la cabecera CLZO.

Lo que **no** se toca: los archivos de tipo 3/4/5. Para reemplazar uno de esos
habría que reproducir Panama o Camellia/Twofish/XTEA-CTR y sus claves, y no
hace falta para cambiar una IP.

## Uso

```bash
python3 tools/m2pack/m2pack.py -p /ruta/al/pack info
python3 tools/m2pack/m2pack.py -p /ruta/al/pack ls
python3 tools/m2pack/m2pack.py -p /ruta/al/pack cat serverinfo.py
python3 tools/m2pack/m2pack.py -p /ruta/al/pack verify
```

`verify` recompone todos los archivos, comprueba CRC y busca solapes entre
blobs. Es la prueba de que entendemos el pack antes de escribir nada.

Para escribir, siempre sobre una copia:

```bash
python3 tools/m2pack/m2pack.py -p copia/ set serverinfo.py nuevo_serverinfo.py
python3 tools/m2pack/m2pack.py -p copia/ cat serverinfo.py
```

`set` guarda `root.eix.bak` y `root.epk.bak` la primera vez.
