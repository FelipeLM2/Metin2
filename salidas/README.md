# Salidas

Volcados crudos de comandos que el agente necesita leer. Aquí **sí** escribe el
usuario; el agente solo lee.

## Convención

```
YYYY-MM-DD-bNN-tema.txt
```

Mismo nombre que el paso que las generó (`pasos/2026-11-07-b01-recon-eterpack.md`
→ `salidas/2026-11-07-b01-recon-eterpack.txt`).

## Reglas

1. **Nada de credenciales.** Aunque sean las de fábrica. El repo es público.
2. Pasar siempre `tools/sanitize.sh` antes del commit y revisar el `git diff`.
3. Salida **completa**, no resumida a mano: los errores y los avisos son la
   mitad de la información.
4. Si el volcado pasa de ~2000 líneas, subirlo igual: el agente filtra.

## Lo que NO va aquí

- `CONFIG`, `conf.txt`, `my.cnf` (tienen contraseñas).
- Dumps `.sql`, logs de MariaDB, `syserr` con datos de cuentas.
- Binarios, `.epk`/`.eix`, capturas de pantalla del cliente.

El `.gitignore` de la raíz ya bloquea esos formatos; no forzar con `git add -f`.
