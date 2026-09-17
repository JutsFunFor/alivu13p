#!/usr/bin/env python3
"""Read the header a .bit file carries about itself.

A bitstream is not anonymous. Vivado writes a short ASCII header in front of the
configuration data naming the design, the exact part, and when it was built. That makes
it checkable rather than trusted: a file published as "the DDR4 design for this board"
can be shown to be built for `xcvu13p-fhgb2104-2L-e` and not for something else, which
matters because programming the wrong part fails in ways that look like a bad board.

Format, which has not changed in many releases of the tools:

    2 bytes  length of the leading field (0x0009)
    9 bytes  magic
    2 bytes  0x0001
    1 byte   'a', then for each of 'a' 'b' 'c' 'd': 2-byte big-endian length
             and a NUL-terminated string
    1 byte   'e', then a 4-byte big-endian length and the configuration data
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

FIELDS = {
    "a": "design",     # top module, plus the tool options it was built with
    "b": "part",
    "c": "date",
    "d": "time",
}


def read_header(path: Path) -> dict:
    with path.open("rb") as handle:
        blob = handle.read(4096)
    length = struct.unpack_from(">H", blob, 0)[0]
    offset = 2 + length + 2          # magic, then the 0x0001 marker
    out: dict[str, object] = {}
    while offset < len(blob):
        key = chr(blob[offset])
        offset += 1
        if key == "e":
            out["bitstream_bytes"] = struct.unpack_from(">I", blob, offset)[0]
            break
        if key not in FIELDS:
            raise ValueError(f"{path}: unexpected header field {key!r} at offset {offset}")
        size = struct.unpack_from(">H", blob, offset)[0]
        offset += 2
        value = blob[offset:offset + size].rstrip(b"\x00").decode("ascii", "replace")
        offset += size
        out[FIELDS[key]] = value
    out["file_bytes"] = path.stat().st_size
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: bitstream_info.py <file.bit> [...]", file=sys.stderr)
        return 2
    for name in sys.argv[1:]:
        path = Path(name)
        info = read_header(path)
        design = info.get("design", "")
        # The design field is a semicolon-separated list; the top module comes first.
        top = design.split(";")[0]
        print(f"{path}")
        print(f"  top       {top}")
        print(f"  part      {info.get('part')}")
        print(f"  built     {info.get('date')} {info.get('time')}")
        print(f"  payload   {info.get('bitstream_bytes')} bytes of {info['file_bytes']}")
        for piece in design.split(";")[1:]:
            print(f"  {piece.strip()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
