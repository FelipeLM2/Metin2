# Pasos

Instrucciones accionables, escritas por el agente para ejecutar en la VM
correspondiente. Son **efímeras**: se cumplen, se archivan y se sustituyen por
el siguiente paso. La documentación permanente vive en `docs/`.

## Convención

```
YYYY-MM-DD-bNN-tema.md
```

- `bNN` = número de bloque de la fase en curso (`b01`, `b02`, …).
- Cada documento: objetivo, comandos listos para copiar, resultado esperado y
  qué hacer si falla.

## Ciclo

```bash
cd ~/metin2-docs        # clon en CachyOS
git pull
```

1. Abrir el `.md` del paso actual y copiar sus bloques.
2. Ejecutar en la VM indicada.
3. Guardar la salida en `salidas/` (los documentos ya traen el comando).
4. `tools/sanitize.sh`, `git add`, `commit`, `push`.
5. Avisar al agente: lee la salida del repo y escribe el paso siguiente.
