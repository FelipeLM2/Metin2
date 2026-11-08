# B05 — Cerrar la Fase B: prueba en el cliente sin `portproxy`

**Fecha:** 2026-11-08
**Máquinas:** cliente Windows 10 (paso 1) y CachyOS (paso 2).
**Riesgo:** ninguno. Solo se lee el estado del cliente; no se cambia nada.

## Por qué este paso

La parte del host de B04 quedó perfecta: `verify` OK antes y después, `diff` de
una sola línea, `serverinfo.py` de 1689 B → blob de 701 B en su hueco de 768, e
ISO creada con:

```
a3d02f6caf8c0073f3448124f8645ca0c43d853826fb7e5cc84f4d07164d58e3  root.eix
0396d0be9f2f702b7f0198542dfb1cbcaebaf93acb62728c7df77a7ca18e1053  root.epk
```

Pero la transcripción del cliente se perdió: `Start-Transcript` + `Read-Host`
se atascaron al pulsar Enter y el archivo no llegó al disco `B04RET`. Como el
login sí funcionó, lo único que falta es **dejar constancia** de que el cliente
usa el pack nuevo y ya no depende del `portproxy`.

Este bloque no usa `Start-Transcript` ni `Read-Host`: vuelca todo a un archivo
con `*> $log` y lo copia al disco de retorno.

## Paso 1 — Cliente Windows

1. Arranca la VM y **abre el cliente**, hasta la pantalla de login o dentro del
   juego (así hay conexiones TCP vivas que capturar).
2. Abre **PowerShell como administrador** (`netsh` lo necesita) y pega:

```powershell
$ErrorActionPreference = "Continue"
$log = "$env:TEMP\b05.txt"

& {
  "== fecha =="
  Get-Date
  ""
  "== procesos del cliente =="
  Get-Process | Where-Object { $_.ProcessName -match "metin2|client" } |
      Select-Object ProcessName, Id | Format-Table -Auto
  ""
  "== pack en uso =="
  $eix = @(Get-ChildItem -Path C:\ -Filter root.eix -Recurse -ErrorAction SilentlyContinue |
           Where-Object { Test-Path (Join-Path $_.DirectoryName "root.epk") })
  $eix | Select-Object -ExpandProperty FullName
  if ($eix.Count -ne 1) { "AVISO: hay $($eix.Count) packs" }
  $pack = $eix[0].DirectoryName
  Get-Item "$pack\root.eix", "$pack\root.epk" |
      Select-Object FullName, Length, LastWriteTime | Format-List
  Get-FileHash "$pack\root.eix", "$pack\root.epk" -Algorithm SHA256 |
      Format-List Path, Hash
  ""
  "== red =="
  Get-NetIPAddress -AddressFamily IPv4 |
      Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
      Format-Table InterfaceAlias, IPAddress, PrefixLength -Auto
  ""
  "== conexiones al servidor =="
  Get-NetTCPConnection -ErrorAction SilentlyContinue |
      Where-Object { $_.RemoteAddress -eq "10.10.10.10" } |
      Select-Object LocalPort, RemoteAddress, RemotePort, State |
      Format-Table -Auto
  ""
  "== portproxy =="
  netsh interface portproxy show all
  ""
  "== pruebas de puerto =="
  "11000: " + (Test-NetConnection 10.10.10.10 -Port 11000 -InformationLevel Quiet)
  "13000: " + (Test-NetConnection 10.10.10.10 -Port 13000 -InformationLevel Quiet)
} *> $log

$ret = Get-Volume | Where-Object { $_.FileSystemLabel -eq "B04RET" }
if (-not $ret) { "ERROR: no veo el disco B04RET" } else {
    Copy-Item $log "$($ret.DriveLetter):\b05.txt" -Force
    Get-ChildItem "$($ret.DriveLetter):"
    Get-Content "$($ret.DriveLetter):\b05.txt"
}
""
"Ya puedes apagar la VM:  Stop-Computer"
```

Si no aparece el disco `B04RET`, apaga la VM y vuelve a añadirlo en
`virt-manager` (**Add Hardware** → *Storage* → *Disk device*, bus SATA,
formato `raw`, `~/metin2lab/work/b04/retorno.img`).

3. Apaga la VM (`Stop-Computer`).

### Resultado esperado

- `Length` de `root.eix` = **17292** (el nuevo índice plano; el viejo era 2968)
  y `root.epk` = **520704**.
- Los dos `Hash` coinciden con los de arriba (`a3d02f…` y `0396d0…`).
- Bajo *conexiones al servidor* aparece al menos una línea con
  `RemoteAddress 10.10.10.10` en `ESTABLISHED` (puerto 13000 o 11000).
- `netsh interface portproxy show all` no lista nada.
- `11000: True` y `13000: True`.

## Paso 2 — Recoger y publicar (CachyOS)

```bash
cd ~/metin2-docs

W=~/metin2lab/work/b04
MNT=/mnt/b04ret
sudo mkdir -p "$MNT"
if ! sudo mount -o ro,loop "$W/retorno.img" "$MNT" 2>/dev/null; then
  sudo fsck.vfat -a "$W/retorno.img"
  sudo mount -o ro,loop "$W/retorno.img" "$MNT"
fi
ls -l "$MNT"

{
  echo "== 0. hashes del pack parcheado (host) =="
  sha256sum "$W/root.eix" "$W/root.epk"
  echo
  echo "== 1. informe del cliente =="
  cat "$MNT/b05.txt"
} > salidas/2026-11-08-b05-verificacion-cliente.txt

sudo umount "$MNT"
wc -l salidas/2026-11-08-b05-verificacion-cliente.txt
```

Publicar:

```bash
cd ~/metin2-docs
tools/sanitize.sh salidas/2026-11-08-b05-verificacion-cliente.txt
git add salidas/2026-11-08-b05-verificacion-cliente.txt
git commit -m "Salida B05: cliente usando el pack nuevo sin portproxy"
git push
```

Avisa: «B05 subido».

## Si algo no cuadra

| Síntoma | Qué hacer |
|---|---|
| Hash distinto de `a3d02f…` | El pack no llegó al cliente. Copiar otra vez desde la ISO (paso 2 de B04). |
| `root.eix` mide 2968 | Sigue el pack viejo; el `Copy-Item` no se aplicó. |
| `portproxy` sigue con reglas | Ejecutar `netsh interface portproxy reset` y repetir el login. |
| No hay conexiones a `10.10.10.10` | El cliente no está abierto o no está logueado al ejecutar el bloque. |
| `Test-NetConnection` en `False` | Revisar `ipconfig`: debe ser `10.10.10.20/24` sin gateway. |

## Qué hará el agente con la salida

1. Confirmar que el cliente usa el pack nuevo y que el `portproxy` está vacío.
2. Cerrar la Fase B en la bitácora y el plan.
3. Preparar la Fase C (portátil + adaptador USB-Ethernet para `br-lab`).
