# Tools

Scripts propios del proyecto. Todos se escriben desde cero y se auditan antes
de ejecutarse; nada de binarios de terceros.

## Previsto

- **`m2pack/`** — lector/escritor de packs EterPack (`root.eix` + `root.epk`):
  - `ls`: listar los archivos del pack con tamaño y tipo de compresión.
  - `cat`: extraer un archivo concreto.
  - `set`: reemplazar un archivo (por ejemplo `serverinfo.py`).

  Dependencias: Python 3 y `liblzo2` vía `ctypes` (LlZO solo hace falta para
  leer los archivos comprimidos del pack original).

## Reglas

- Un script = un archivo, sin instalación global.
- Nada de `curl | bash` ni paquetes sin revisar.
- Si una herramienta ajena es inevitable, se copia aquí el fragmento usado y
  se documenta de dónde sale y con qué licencia.
