#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""m2pack — lector/escritor mínimo de packs EterPack (Metin2 40250 / TMP4).

Formato, según ClientVS22/source/EterPack (volcado en
salidas/2026-11-07-b02-fuente-eterpack.txt):

  .eix = índice. Dos formas posibles:
    * plano:   'EPKD' | u32 version(=2) | i32 count | count x TEterPackIndex
    * cifrado: CLZO('MCOZ', encrypt_size, compressed_size, real_size) + payload
               (LZO + TEA) con la clave s_adwEterPackKey

  .epk = concatenación de blobs, uno por entrada del índice:
    * tipo 0 (none)      datos crudos
    * tipo 1 (compress)  CLZO sin cifrar (solo LZO)
    * tipo 2 (security)  CLZO cifrado (LZO + TEA) con s_adwEterPackSecurityKey
    * tipo 3/4/5         Panama / CSHybridCrypt: NO soportados (no se tocan)

  Layout real de un blob CLZO (CLZObject::Compress / Encrypt):
    offset 0   THeader (16 B): 'MCOZ' | encrypt_size | compressed_size | real_size
    offset 16  DWORD 'MCOZ'  (segundo fourcc, forma parte del área cifrada)
    offset 20  stream LZO de compressed_size bytes
  O sea, el stream LZO empieza en el offset 20, no en el 16. Cuando el blob
  está cifrado, TEA cubre desde el offset 16 (incluido el 'MCOZ' interno)
  durante encrypt_size bytes; GetSize() = 16 + 4 + encrypt_size.

  TEterPackIndex (192 bytes, little endian, #pragma pack(4)):
    u32  id
    char filename[161]
    u32  filename_crc      = CRC32(filename en minúsculas, '\\' -> '/')
    i32  real_data_size    = hueco reservado en el .epk (múltiplo de 256)
    i32  data_size         = bytes que ocupa el blob en el .epk
    u32  data_crc          = CRC32(blob almacenado); solo se comprueba en tipo 2/3
    i32  data_position     = offset absoluto en el .epk
    u8   compressed_type

Uso:
    python3 m2pack.py info
    python3 m2pack.py ls
    python3 m2pack.py cat serverinfo.py
    python3 m2pack.py verify
    python3 m2pack.py set serverinfo.py nuevo.py [--type none|compress]

`set` escribe con tipo 0 por defecto (datos crudos, sin LZO ni cifrado):
el cliente lo lee igual y evita tener que reproducir el cifrado.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import struct
import sys
import zlib
from dataclasses import dataclass, replace
from pathlib import Path

# ---------------------------------------------------------------------------
# Constantes del formato
# ---------------------------------------------------------------------------

MAGIC_INDEX = b"EPKD"       # eterpack::c_IndexCC / c_PackCC
MAGIC_LZO = b"MCOZ"         # CLZObject::ms_dwFourCC
VERSION = 2

INDEX_HEADER_FMT = "<IIi"   # fourcc, version, count
INDEX_HEADER_SIZE = struct.calcsize(INDEX_HEADER_FMT)   # 12

ENTRY_FMT = "<I161s3xIiiIib3x"
ENTRY_SIZE = struct.calcsize(ENTRY_FMT)
assert ENTRY_SIZE == 192, ENTRY_SIZE

CLZO_HEADER_FMT = "<IIII"   # fourcc, encrypt_size, compressed_size, real_size
CLZO_HEADER_SIZE = struct.calcsize(CLZO_HEADER_FMT)     # 16

TYPE_NAMES = {
    0: "none",
    1: "compress",
    2: "security",
    3: "panama",
    4: "hybrid",
    5: "hybrid+sdb",
}

# EterPack.cpp
ETERPACK_KEY = [45129401, 92367215, 681285731, 1710201]
SECURITY_KEY = [78952482, 527348324, 1632942, 486274726]

MASK = 0xFFFFFFFF
DELTA = 0x9E3779B9
ROUNDS = 32


class PackError(Exception):
    pass


# ---------------------------------------------------------------------------
# CRC32 (EterBase/CRC32.cpp: misma tabla y mismo cálculo que zlib.crc32)
# ---------------------------------------------------------------------------

def crc32(data: bytes) -> int:
    return zlib.crc32(data) & MASK


def pack_name_crc(name: str) -> int:
    """CRC32 del nombre tal como lo normaliza inlineConvertPackFilename()."""
    normalized = name.replace("\\", "/").lower()
    return crc32(normalized.encode("latin-1", "replace"))


# ---------------------------------------------------------------------------
# TEA / XTEA
#
# EterBase/tea.cpp implementa la variante de la referencia xtea.ps:
#   y += (((z<<4) ^ (z>>5)) + z) ^ (sum + key[sum & 3]);  sum += delta
#   z += (((y<<4) ^ (y>>5)) + y) ^ (sum + key[(sum>>11) & 3])
# Se incluye también la variante TEA clásica por si el cliente usara esa.
# ---------------------------------------------------------------------------

def _tea_decrypt_words_ref(y: int, z: int, key) -> tuple[int, int]:
    s = (DELTA * ROUNDS) & MASK
    for _ in range(ROUNDS):
        z = (z - ((((y << 4) ^ (y >> 5)) + y) ^ (s + key[(s >> 11) & 3]))) & MASK
        s = (s - DELTA) & MASK
        y = (y - ((((z << 4) ^ (z >> 5)) + z) ^ (s + key[s & 3]))) & MASK
    return y, z


def _tea_encrypt_words_ref(y: int, z: int, key) -> tuple[int, int]:
    s = 0
    for _ in range(ROUNDS):
        y = (y + ((((z << 4) ^ (z >> 5)) + z) ^ (s + key[s & 3]))) & MASK
        s = (s + DELTA) & MASK
        z = (z + ((((y << 4) ^ (y >> 5)) + y) ^ (s + key[(s >> 11) & 3]))) & MASK
    return y, z


def _tea_decrypt_words_classic(y: int, z: int, key) -> tuple[int, int]:
    s = (DELTA * ROUNDS) & MASK
    for _ in range(ROUNDS):
        z = (z - ((((y << 4) + key[2]) ^ ((y + s) & MASK)) ^ ((y >> 5) + key[3]))) & MASK
        s = (s - DELTA) & MASK
        y = (y - ((((z << 4) + key[0]) ^ ((z + s) & MASK)) ^ ((z >> 5) + key[1]))) & MASK
    return y, z


def _tea_encrypt_words_classic(y: int, z: int, key) -> tuple[int, int]:
    s = 0
    for _ in range(ROUNDS):
        y = (y + ((((z << 4) + key[0]) ^ ((z + s) & MASK)) ^ ((z >> 5) + key[1]))) & MASK
        s = (s + DELTA) & MASK
        z = (z + ((((y << 4) + key[2]) ^ ((y + s) & MASK)) ^ ((y >> 5) + key[3]))) & MASK
    return y, z


_DECRYPT = {"ref": _tea_decrypt_words_ref, "classic": _tea_decrypt_words_classic}
_ENCRYPT = {"ref": _tea_encrypt_words_ref, "classic": _tea_encrypt_words_classic}


def tea_crypt(data: bytes, key, variant: str, decrypt: bool) -> bytes:
    # tea_encrypt/tea_decrypt redondean a múltiplo de 8 (rellenan con ceros).
    if len(data) % 8:
        data = data + b"\0" * (8 - len(data) % 8)
    n = len(data) // 4
    words = list(struct.unpack(f"<{n}I", data))
    fn = (_DECRYPT if decrypt else _ENCRYPT)[variant]
    for i in range(0, n, 2):
        words[i], words[i + 1] = fn(words[i], words[i + 1], key)
    return struct.pack(f"<{n}I", *words)


# ---------------------------------------------------------------------------
# LZO (liblzo2 vía ctypes)
# ---------------------------------------------------------------------------

class Lzo:
    def __init__(self) -> None:
        candidates = ["liblzo2.so.2", "liblzo2.so", "liblzo2.dylib"]
        found = ctypes.util.find_library("lzo2")
        if found:
            candidates.insert(0, found)
        self.lib = None
        for name in candidates:
            try:
                self.lib = ctypes.CDLL(name)
                break
            except OSError:
                continue
        if self.lib is None:
            raise PackError(
                "no encuentro liblzo2. En CachyOS: sudo pacman -S lzo"
            )

        self.lib.lzo1x_decompress_safe.restype = ctypes.c_int
        self.lib.lzo1x_decompress_safe.argtypes = [
            ctypes.c_char_p,
            ctypes.c_size_t,
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_size_t),
            ctypes.c_void_p,
        ]

    def decompress(self, src: bytes, out_size: int) -> bytes:
        if out_size <= 0:
            return b""
        dst = (ctypes.c_ubyte * out_size)()
        dst_len = ctypes.c_size_t(out_size)
        rc = self.lib.lzo1x_decompress_safe(
            src, len(src), dst, ctypes.byref(dst_len), None
        )
        if rc != 0:
            raise PackError(f"lzo1x_decompress_safe falló (código {rc})")
        if dst_len.value != out_size:
            raise PackError(
                f"LZO devolvió {dst_len.value} bytes, se esperaban {out_size}"
            )
        return bytes(dst)


_lzo: Lzo | None = None


def lzo() -> Lzo:
    global _lzo
    if _lzo is None:
        _lzo = Lzo()
    return _lzo


# ---------------------------------------------------------------------------
# Modelo
# ---------------------------------------------------------------------------

@dataclass
class Entry:
    id: int
    filename: str
    filename_crc: int
    real_data_size: int
    data_size: int
    data_crc: int
    data_position: int
    ctype: int

    @property
    def is_free(self) -> bool:
        return self.filename_crc == 0 and not self.filename

    @property
    def type_name(self) -> str:
        return TYPE_NAMES.get(self.ctype, f"desconocido({self.ctype})")


@dataclass
class Pack:
    packdir: Path
    index_path: Path
    data_path: Path
    index_variant: str          # "plano" | "ref" | "classic"
    entries: list[Entry]
    index_bytes: bytes
    data: bytes
    index_clzo: tuple[int, int, int] | None = None   # (enc, comp, real)

    @property
    def tea_variant(self) -> str:
        """Variante deducida del índice; si el índice venía plano, la de xtea.ps."""
        return self.index_variant if self.index_variant in ("ref", "classic") else "ref"

    def find(self, name: str) -> Entry:
        want = name.replace("\\", "/").lower()
        matches = [e for e in self.entries if e.filename.lower() == want]
        if not matches:
            # segundo intento: por nombre base
            base = want.rsplit("/", 1)[-1]
            matches = [e for e in self.entries if e.filename.lower().rsplit("/", 1)[-1] == base]
        if not matches:
            raise PackError(f"no existe en el índice: {name}")
        if len(matches) > 1:
            raise PackError(
                "nombre ambiguo, hay varias coincidencias:\n  "
                + "\n  ".join(e.filename for e in matches)
            )
        return matches[0]


# ---------------------------------------------------------------------------
# Lectura del índice
# ---------------------------------------------------------------------------

def _parse_index(body: bytes) -> list[Entry]:
    if len(body) < INDEX_HEADER_SIZE:
        raise PackError("índice demasiado corto")
    magic, version, count = struct.unpack_from(INDEX_HEADER_FMT, body, 0)
    if magic != int.from_bytes(MAGIC_INDEX, "little"):
        raise PackError(
            f"magic de índice inesperado: {body[:4]!r} (se esperaba {MAGIC_INDEX!r})"
        )
    if version != VERSION:
        raise PackError(f"versión de índice {version}, se esperaba {VERSION}")
    if count < 0 or count > 1_000_000:
        raise PackError(f"número de entradas absurdo: {count}")
    need = INDEX_HEADER_SIZE + count * ENTRY_SIZE
    if len(body) < need:
        raise PackError(
            f"índice truncado: {len(body)} bytes, hacen falta {need} "
            f"({count} entradas × {ENTRY_SIZE})"
        )

    entries = []
    for i in range(count):
        off = INDEX_HEADER_SIZE + i * ENTRY_SIZE
        raw = struct.unpack_from(ENTRY_FMT, body, off)
        name = raw[1].split(b"\0", 1)[0].decode("latin-1", "replace")
        entries.append(
            Entry(
                id=raw[0],
                filename=name,
                filename_crc=raw[2],
                real_data_size=raw[3],
                data_size=raw[4],
                data_crc=raw[5],
                data_position=raw[6],
                ctype=raw[7],
            )
        )
    return entries


def _clzo_payload(blob: bytes) -> tuple[int, int, int, bytes]:
    """Cabecera CLZO + payload.

    Devuelve (encrypt_size, compressed_size, real_size, payload), donde
    payload empieza justo en el DWORD 'MCOZ' interno (offset 16 del blob).
    El stream LZO, por tanto, es payload[4:4+compressed_size].
    """
    if len(blob) < CLZO_HEADER_SIZE:
        raise PackError("blob CLZO demasiado corto")
    fourcc, enc, comp, real = struct.unpack_from(CLZO_HEADER_FMT, blob, 0)
    if fourcc != int.from_bytes(MAGIC_LZO, "little"):
        raise PackError(f"se esperaba cabecera MCOZ, hay {blob[:4]!r}")

    stored = enc if enc else comp
    if CLZO_HEADER_SIZE + stored > len(blob):
        raise PackError(
            f"blob CLZO truncado: cabecera dice {stored} bytes, "
            f"solo hay {len(blob) - CLZO_HEADER_SIZE}"
        )
    if enc and comp + 4 > enc:
        raise PackError(
            f"blob CLZO incoherente: compressed_size={comp} no cabe en "
            f"encrypt_size={enc} (ni con el 'MCOZ' interno)"
        )
    return enc, comp, real, blob[CLZO_HEADER_SIZE:]


def _require_inner_fourcc(plain: bytes, who: str) -> None:
    if plain[:4] != MAGIC_LZO:
        raise PackError(
            f"{who}: falta el fourcc 'MCOZ' interno tras la cabecera "
            f"(hay {plain[:4]!r})"
        )


def load_pack(packdir: Path, name: str = "root") -> Pack:
    index_path = packdir / f"{name}.eix"
    data_path = packdir / f"{name}.epk"
    if not index_path.is_file():
        raise PackError(f"no existe {index_path}")
    if not data_path.is_file():
        raise PackError(f"no existe {data_path}")

    raw = index_path.read_bytes()
    index_clzo = None
    if raw[:4] == MAGIC_INDEX:
        variant = "plano"
        body = raw
    elif raw[:4] == MAGIC_LZO:
        enc, comp, real, payload = _clzo_payload(raw)
        index_clzo = (enc, comp, real)
        encrypted = payload[:enc]
        body = None
        variant = ""
        errors = []
        for candidate in ("ref", "classic"):
            try:
                plain = tea_crypt(encrypted, ETERPACK_KEY, candidate, decrypt=True)
                _require_inner_fourcc(plain, f"índice ({candidate})")
                out = lzo().decompress(plain[4:4 + comp], real)
            except PackError as exc:
                errors.append(f"{candidate}: {exc}")
                continue
            if out[:4] == MAGIC_INDEX:
                body = out
                variant = candidate
                break
            errors.append(f"{candidate}: descifra pero no empieza por EPKD")
        if body is None:
            raise PackError(
                "no se pudo descifrar el índice con ninguna variante TEA:\n  "
                + "\n  ".join(errors)
            )
    else:
        raise PackError(
            f"el índice no empieza por EPKD ni MCOZ: {raw[:8]!r}"
        )

    entries = _parse_index(body)
    return Pack(
        packdir=packdir,
        index_path=index_path,
        data_path=data_path,
        index_variant=variant,
        entries=entries,
        index_bytes=body,
        data=data_path.read_bytes(),
        index_clzo=index_clzo,
    )


# ---------------------------------------------------------------------------
# Extracción de un archivo
# ---------------------------------------------------------------------------

def decode_blob(pack: Pack, entry: Entry, blob: bytes) -> bytes:
    """Devuelve el contenido real a partir del blob almacenado en el .epk."""
    if entry.ctype == 0:
        return blob

    if entry.ctype not in (1, 2):
        raise PackError(
            f"{entry.filename}: tipo {entry.ctype} ({entry.type_name}) no soportado"
        )

    # El cliente solo comprueba el CRC de los tipos 2 y 3 (EterPack.cpp).
    if entry.ctype in (2, 3) and crc32(blob) != entry.data_crc:
        raise PackError(f"{entry.filename}: data_crc no coincide (archivo dañado)")

    enc, comp, real, payload = _clzo_payload(blob)

    if entry.ctype == 1:
        _require_inner_fourcc(payload, entry.filename)
        return lzo().decompress(payload[4:4 + comp], real)

    if enc == 0:
        raise PackError(f"{entry.filename}: tipo 2 sin tamaño cifrado")

    # Si el índice venía plano no sabemos la variante; se prueban las dos y
    # se acepta la que produce un LZO válido del tamaño esperado.
    variants = [pack.tea_variant]
    variants += [v for v in ("ref", "classic") if v != pack.tea_variant]
    errors = []
    for variant in variants:
        try:
            plain = tea_crypt(payload[:enc], SECURITY_KEY, variant, decrypt=True)
            _require_inner_fourcc(plain, f"{entry.filename} ({variant})")
            return lzo().decompress(plain[4:4 + comp], real)
        except PackError as exc:
            errors.append(f"{variant}: {exc}")

    raise PackError(
        f"{entry.filename}: no se pudo descifrar/descomprimir\n  "
        + "\n  ".join(errors)
    )


def read_entry(pack: Pack, entry: Entry) -> bytes:
    pos = entry.data_position
    size = entry.data_size
    if pos < 0 or size < 0 or pos + size > len(pack.data):
        raise PackError(
            f"{entry.filename}: posición/tamaño fuera del .epk "
            f"({pos}+{size} > {len(pack.data)})"
        )
    return decode_blob(pack, entry, pack.data[pos:pos + size])


# ---------------------------------------------------------------------------
# Serialización del índice
# ---------------------------------------------------------------------------

def serialize_index(entries: list[Entry]) -> bytes:
    out = bytearray()
    out += struct.pack(
        INDEX_HEADER_FMT,
        int.from_bytes(MAGIC_INDEX, "little"),
        VERSION,
        len(entries),
    )
    for e in entries:
        name = e.filename.encode("latin-1", "replace")
        if len(name) > 160:
            raise PackError(f"nombre demasiado largo: {e.filename!r}")
        out += struct.pack(
            ENTRY_FMT,
            e.id,
            name,
            e.filename_crc,
            e.real_data_size,
            e.data_size,
            e.data_crc,
            e.data_position,
            e.ctype,
        )
    return bytes(out)


# ---------------------------------------------------------------------------
# Comandos
# ---------------------------------------------------------------------------

def cmd_info(pack: Pack, args) -> int:
    print(f"índice : {pack.index_path}")
    print(f"datos  : {pack.data_path}")
    print(f"formato: {pack.index_variant} "
          f"({pack.index_path.stat().st_size} bytes en disco, "
          f"{len(pack.index_bytes)} bytes de índice plano)")
    if pack.index_clzo is not None:
        enc, comp, real = pack.index_clzo
        print(f"  CLZO : encrypt_size={enc} compressed_size={comp} "
              f"real_size={real}")
    print(f"epk    : {len(pack.data)} bytes")
    print(f"entradas: {len(pack.entries)}")
    reales = [e for e in pack.entries if not e.is_free]
    print(f"  con datos: {len(reales)}")
    print(f"  libres   : {len(pack.entries) - len(reales)}")
    used = sum(e.data_size for e in reales)
    print(f"  bytes usados en blobs: {used}")
    return 0


def cmd_ls(pack: Pack, args) -> int:
    show_all = args.all
    print(f"{'id':>3}  {'tipo':<10} {'posición':>10} {'real':>8} {'blob':>8}  nombre")
    print("-" * 78)
    for e in pack.entries:
        if e.is_free and not show_all:
            continue
        name = e.filename or "<libre>"
        print(
            f"{e.id:>3}  {e.type_name:<10} {e.data_position:>10} "
            f"{e.real_data_size:>8} {e.data_size:>8}  {name}"
        )
    if not show_all:
        print(f"\n({sum(1 for e in pack.entries if e.is_free)} entradas libres ocultas; usa --all)")
    return 0


def cmd_cat(pack: Pack, args) -> int:
    entry = pack.find(args.name)
    data = read_entry(pack, entry)
    if args.out:
        Path(args.out).write_bytes(data)
        print(f"escrito {args.out} ({len(data)} bytes)", file=sys.stderr)
    else:
        sys.stdout.buffer.write(data)
    return 0


def cmd_verify(pack: Pack, args) -> int:
    problems = 0
    print("== cabeceras ==")
    for e in pack.entries:
        if e.is_free:
            continue
        if pack_name_crc(e.filename) != e.filename_crc:
            print(f"  ! {e.filename}: filename_crc no coincide")
            problems += 1
        if e.data_position < 0 or e.data_size < 0 \
                or e.data_position + e.data_size > len(pack.data):
            print(f"  ! {e.filename}: fuera del .epk")
            problems += 1
            continue
        blob = pack.data[e.data_position:e.data_position + e.data_size]
        # En tipo 2/3 el CRC lo comprueba decode_blob (como hace el cliente).
        if e.ctype not in (2, 3) and crc32(blob) != e.data_crc:
            print(f"  ! {e.filename}: data_crc no coincide")
            problems += 1
        if e.ctype in (1, 2):
            try:
                out = decode_blob(pack, e, blob)
                if len(out) != e.real_data_size:
                    print(f"  ! {e.filename}: descomprime {len(out)} != real {e.real_data_size}")
                    problems += 1
            except PackError as exc:
                print(f"  ! {e.filename}: {exc}")
                problems += 1
        elif e.ctype == 0:
            if e.data_size > e.real_data_size:
                print(f"  ! {e.filename}: datos ({e.data_size}) > hueco ({e.real_data_size})")
                problems += 1
        else:
            print(f"  . {e.filename}: tipo {e.ctype} no comprobado")

    print("\n== solapes ==")
    occupied = sorted(
        (e.data_position, e.data_position + e.real_data_size, e.filename)
        for e in pack.entries
        if not e.is_free and e.real_data_size > 0
    )
    last_end = 0
    last_name = "<inicio>"
    for start, end, name in occupied:
        if start < last_end:
            print(f"  ! {name} empieza en {start}, dentro de {last_name} (acaba en {last_end})")
            problems += 1
        last_end = max(last_end, end)
        last_name = name

    print()
    if problems:
        print(f"RESULTADO: {problems} problema(s)")
        return 1
    print("RESULTADO: OK")
    return 0


def cmd_set(pack: Pack, args) -> int:
    entry = pack.find(args.name)
    new = Path(args.file).read_bytes()

    pack_type = {"none": 0, "compress": 1}[args.type]
    if pack_type == 1:
        raise PackError("tipo 1 no implementado todavía; usa --type none")

    data = bytearray(pack.data)

    # ¿Cabe en el hueco reservado sin pisar otra entrada?
    fits = (
        len(new) <= entry.real_data_size
        and entry.data_position >= 0
        and entry.data_position + entry.real_data_size <= len(data)
    )
    if fits:
        for other in pack.entries:
            if other is entry or other.is_free or other.real_data_size <= 0:
                continue
            a0, a1 = entry.data_position, entry.data_position + entry.real_data_size
            b0, b1 = other.data_position, other.data_position + other.real_data_size
            if a0 < b1 and b0 < a1:
                fits = False
                break

    if fits:
        pos = entry.data_position
        end = pos + entry.real_data_size
        data[pos:pos + len(new)] = new
        data[pos + len(new):end] = b"\0" * (end - pos - len(new))
        real = entry.real_data_size
        how = f"en su hueco ({pos}, {real} bytes)"
    else:
        pos = len(data)
        real = len(new) + (-len(new) % 256)
        data += new
        data += b"\0" * (real - len(new))
        how = f"al final del .epk ({pos}, hueco nuevo de {real} bytes)"

    updated = replace(
        entry,
        real_data_size=real,
        data_size=len(new),
        data_crc=crc32(new),
        data_position=pos,
        ctype=pack_type,
    )
    entries = [updated if e is entry else e for e in pack.entries]

    # Copias de seguridad
    bak_i = pack.index_path.with_suffix(pack.index_path.suffix + ".bak")
    bak_d = pack.data_path.with_suffix(pack.data_path.suffix + ".bak")
    if not bak_i.exists():
        bak_i.write_bytes(pack.index_path.read_bytes())
    if not bak_d.exists():
        bak_d.write_bytes(pack.data_path.read_bytes())

    pack.data_path.write_bytes(bytes(data))
    pack.index_path.write_bytes(serialize_index(entries))

    print(f"{entry.filename}: {len(new)} bytes, tipo 0, {how}")
    print(f"índice reescrito plano: {pack.index_path} "
          f"({INDEX_HEADER_SIZE + len(entries) * ENTRY_SIZE} bytes)")
    print(f"backups: {bak_i.name}, {bak_d.name}")
    return 0


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="m2pack",
        description="Lector/escritor mínimo de packs EterPack de Metin2 40250.",
    )
    parser.add_argument(
        "-p", "--packdir", default=".",
        help="carpeta con root.eix y root.epk (por defecto: .)",
    )
    parser.add_argument(
        "-n", "--name", dest="packname", default="root",
        help="nombre base del pack, sin extensión (por defecto: root)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("info", help="resumen del índice")

    p_ls = sub.add_parser("ls", help="listar entradas")
    p_ls.add_argument("--all", action="store_true", help="incluir entradas libres")

    p_cat = sub.add_parser("cat", help="extraer un archivo")
    p_cat.add_argument("name")
    p_cat.add_argument("-o", "--out", help="escribir en archivo en vez de stdout")

    sub.add_parser("verify", help="comprobar CRC, tamaños y solapes")

    p_set = sub.add_parser("set", help="reemplazar un archivo")
    p_set.add_argument("name")
    p_set.add_argument("file")
    p_set.add_argument(
        "--type", choices=["none", "compress"], default="none",
        help="tipo con el que se guarda (por defecto none)",
    )

    args = parser.parse_args(argv)

    try:
        pack = load_pack(Path(args.packdir), args.packname)
        handler = {
            "info": cmd_info,
            "ls": cmd_ls,
            "cat": cmd_cat,
            "verify": cmd_verify,
            "set": cmd_set,
        }[args.command]
        return handler(pack, args)
    except PackError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
