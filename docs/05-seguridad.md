# Modelo de seguridad y confianza

## La pregunta

¿Se puede saber con certeza que el cliente y el servidor no tienen malware?

**No.** No existe un método que *demuestre* que un binario cerrado de 1,3 GB
está limpio: ni antivirus, ni VirusTotal, ni analizar imports prueban la
ausencia de una puerta trasera. Lo que sí se puede hacer es bajar la confianza
depositada y acotar el daño.

## Escalera de confianza

| Nivel | Qué aporta | Coste | Riesgo residual |
|---|---|---|---|
| 0. Aislamiento | Nada se puede exfiltrar ni propagar | ya hecho | el binario sigue siendo desconocido |
| 1. Triage estático (imports, strings, entropía) | descarta lo obvio | ~1 h | ofuscación, dropper remoto |
| 2. Vigilancia de red (solo habla con `10.10.10.10`) | detecta C2 al ejecutar | ~30 min | payload dormido sin red |
| 3. Compilar el cliente desde las fuentes incluidas | sustituye el binario ajeno por el propio | 1–2 días | toolchain y libs precompiladas |
| 4. Auditar fuentes y `extern` | confianza casi total en el código | semanas | assets y parsers |

## Lo que se demostró en el servidor

El servidor está en **nivel 3**, y con una particularidad excelente: el build
es **reproducible**. Compilar las fuentes incluidas con el toolchain incluido
produce bytes idénticos a los binarios distribuidos.

Eso demuestra que **los binarios distribuidos corresponden a las fuentes
incluidas** — se descarta la vía "fuente limpia + ejecutable troyanizado".
No demuestra que las fuentes sean benignas; eso se ataca leyendo código, y no
es viable a mano en un árbol de este tamaño. En la práctica se hace con
búsquedas dirigidas: `system(`, `popen`, `exec`, sockets a IPs externas,
`dlopen`, cadenas en base64.

## Contención: la parte que de verdad protege

Un cliente malicioso solo es peligroso si tiene **a dónde enviar** y **qué
robar**. En este montaje:

- Red aislada sin forwarding: no hay ruta a Internet ni a la LAN doméstica.
- Cero datos personales, cuentas, correo o nube en la VM del cliente.
- Sin carpetas compartidas, sin portapapeles, sin USB redirection.
- Snapshots e imagen de disco para volver a cero.

Aunque el `.exe` fuese un troyano, no tiene salida. Regla mental:
**"limpio" no se demuestra; "sin consecuencias" se diseña.**

## Endurecimiento aplicado

| Elemento | Antes | Ahora |
|---|---|---|
| root de FreeBSD | clave de fábrica | rotada |
| root de MariaDB | clave de fábrica | rotada |
| `admin` del juego | clave de fábrica | rotada (`PASSWORD()`) |
| `bind-address` de MariaDB | `*` (0.0.0.0:3306) | `127.0.0.1` |
| `root@%` en MySQL | existía con la clave vieja | eliminado |
| Cuentas anónimas (`''@localhost`, `''@metin2.code`) | existían | eliminadas |

Hallazgo relevante: el informe inicial daba por hecho que MariaDB solo
escuchaba en loopback. No era cierto: `bind-address = *` y `root@%` con la
contraseña de fábrica. Se verificó conectando desde la IP del laboratorio y
obteniendo respuesta; después del cambio, la conexión ya no llega al puerto.

## Pendiente (deliberado)

- Usuario SQL `metin2` con contraseña de fábrica. Está repetido en las
  configuraciones de auth/canales/`db/conf.txt`; se rota en un paso aparte,
  con búsqueda `grep -rl` y prueba de login después.
- `ADMINPAGE_PASSWORD` del auth (la página solo escucha en `127.0.0.1`).
- Cuenta de juego `test`: revisar si tiene personajes antes de borrarla.

## El cliente sigue en nivel 0

El cliente Windows no se ha recompilado. Su aislamiento (red sin salida, sin
datos) es lo que lo hace seguro de usar, no un análisis del binario. La vía
para subir de nivel es compilar `ClientVS22` y comparar comportamiento, y eso
es Fase D.
