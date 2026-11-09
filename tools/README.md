# Tools

Scripts propios del proyecto. Todos se escriben desde cero y se auditan antes
de ejecutarse; nada de binarios de terceros.

## `c01/`

Cliente Wine + DXVK en CachyOS dentro de un *network namespace* con una única
ruta al servidor. Se ejecuta en este orden:

```bash
bash c01/00-diagnostico.sh      # solo lectura
bash c01/10-prefix.sh           # prefijo win32, sin Z:, cliente + pack
bash c01/15-dxvk.sh             # unica descarga (GitHub)
bash c01/20-netns-up.sh         # jaula de red
bash c01/30-run-client.sh       # lanza el cliente (no root)
bash c01/35-check-isolation.sh  # con el juego abierto
bash c01/90-netns-down.sh       # limpia la jaula
```

Detalle y límites: [`c01/README.md`](c01/README.md) y
[`../pasos/2026-11-09-c01-wine-torre.md`](../pasos/2026-11-09-c01-wine-torre.md).

## `m2pack/`

Lector/escritor de packs EterPack (`root.eix` + `root.epk`), en Python 3 con
`liblzo2` por `ctypes`.

```bash
python3 m2pack/m2pack.py -p /ruta/al/pack info
python3 m2pack/m2pack.py -p /ruta/al/pack ls
python3 m2pack/m2pack.py -p /ruta/al/pack cat serverinfo.py
python3 m2pack/m2pack.py -p /ruta/al/pack verify
```

- `ls`: lista los archivos del pack con tamaño, posición y tipo de compresión.
- `cat`: extrae un archivo concreto.
- `verify`: recomputa CRC, tamaños y solapes. Es la prueba de que la lectura es
  correcta antes de escribir nada.
- `set`: reemplaza un archivo (escribe tipo 0 y el índice plano).

Detalle del formato: [`../docs/04-eterpack.md`](../docs/04-eterpack.md).

## `sanitize.sh`

Redactor de secretos para las salidas que se suben al repo público. **No es
infalible**: siempre revisar `git diff` antes del commit.

## Reglas

- Un script = un archivo, sin instalación global.
- Nada de `curl | bash` ni paquetes sin revisar.
- Si una herramienta ajena es inevitable, se copia aquí el fragmento usado y
  se documenta de dónde sale y con qué licencia.
