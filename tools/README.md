# Tools

Scripts propios del proyecto. Todos se escriben desde cero y se auditan antes
de ejecutarse; nada de binarios de terceros.

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
