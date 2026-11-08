# m2pack

Lector/escritor mínimo de packs EterPack de Metin2 40250 (TMP4), escrito desde
cero a partir de `ClientVS22/source/EterPack`.

No usa ninguna herramienta de terceros: Python 3 + `liblzo2` por `ctypes`.

## Requisitos

- Python 3.8 o superior.
- `liblzo2` (en CachyOS/Arch: `sudo pacman -S lzo`).

## Uso

```bash
python3 m2pack.py -p /ruta/al/pack info      # resumen del índice
python3 m2pack.py -p /ruta/al/pack ls        # entradas (--all incluye libres)
python3 m2pack.py -p /ruta/al/pack cat serverinfo.py
python3 m2pack.py -p /ruta/al/pack verify    # CRC, tamaños, solapes
```

`-p` es la carpeta que contiene `root.eix` y `root.epk`. Por defecto usa `.`;
`-n otro` cambia el nombre base del pack.

Escribir (siempre sobre una copia):

```bash
python3 m2pack.py -p copia/ set serverinfo.py nuevo_serverinfo.py
```

`set` escribe el archivo como tipo 0 (sin LZO ni cifrado) y reescribe el `.eix`
en forma plana. Deja `root.eix.bak` y `root.epk.bak` la primera vez.

## Qué soporta

| Operación | Tipos |
|---|---|
| listar | todos |
| extraer | 0 (ninguno), 1 (LZO), 2 (LZO+TEA) |
| verificar | 0, 1, 2 |
| reemplazar | escribe tipo 0 |

Los tipos 3 (Panama) y 4/5 (CSHybridCrypt) se listan pero no se descifran: no
hacen falta para cambiar `serverinfo.py` y reproducirlos sería mucho más
código y más riesgo.

## Por qué el índice se escribe plano

`CEterPack::__BuildIndex` acepta un índice que empiece por `EPKD` (plano) o por
`MCOZ` (cifrado). El cliente lo abre en modo solo lectura, así que no vuelve a
cifrarlo. Escribirlo plano elimina la necesidad de comprimir y cifrar el índice
en la herramienta.

Detalle del formato en [`../../docs/04-eterpack.md`](../../docs/04-eterpack.md).
