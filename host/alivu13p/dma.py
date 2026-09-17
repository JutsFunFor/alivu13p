"""Bulk transfers over the XDMA character devices.

The driver turns each DMA channel into a file whose offset is the AXI address on the
card, so a transfer is a seek plus a read or write. Nothing more exotic is needed, and
using pread/pwrite keeps the offset out of the object's state -- concurrent transfers on
one handle then cannot interfere.
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class Transfer:
    """What a transfer did, and how fast."""

    nbytes: int
    seconds: float

    @property
    def gbytes_per_s(self) -> float:
        return self.nbytes / self.seconds / 1e9 if self.seconds > 0 else float("inf")


class Dma:
    """One host-to-card and one card-to-host channel."""

    def __init__(self, index: int = 0, channel: int = 0):
        self.h2c_path = f"/dev/xdma{index}_h2c_{channel}"
        self.c2h_path = f"/dev/xdma{index}_c2h_{channel}"
        self._h2c = os.open(self.h2c_path, os.O_WRONLY)
        try:
            self._c2h = os.open(self.c2h_path, os.O_RDONLY)
        except Exception:
            os.close(self._h2c)
            raise

    def close(self) -> None:
        os.close(self._h2c)
        os.close(self._c2h)

    def __enter__(self) -> "Dma":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def write(self, addr: int, data: bytes) -> Transfer:
        start = time.perf_counter()
        written = 0
        while written < len(data):
            # A short write is normal for large transfers rather than an error, so the
            # loop is required for correctness and not just for robustness.
            n = os.pwrite(self._h2c, data[written:], addr + written)
            if n <= 0:
                raise OSError(f"write to 0x{addr + written:X} returned {n}")
            written += n
        return Transfer(written, time.perf_counter() - start)

    def read(self, addr: int, nbytes: int) -> tuple[bytes, Transfer]:
        start = time.perf_counter()
        chunks: list[bytes] = []
        got = 0
        while got < nbytes:
            chunk = os.pread(self._c2h, nbytes - got, addr + got)
            if not chunk:
                raise OSError(f"read from 0x{addr + got:X} returned nothing "
                              f"after {got} of {nbytes} bytes")
            chunks.append(chunk)
            got += len(chunk)
        return b"".join(chunks), Transfer(got, time.perf_counter() - start)


def first_difference(a: bytes, b: bytes) -> int | None:
    """Byte offset of the first difference, or None if the buffers match.

    Worth having rather than a bare assert: where a comparison first fails says what
    kind of fault it is. An offset that is a multiple of the transfer width points at a
    whole word going astray; one that repeats at a fixed small stride points at a byte
    lane; a single isolated byte points at the memory itself.
    """
    if len(a) != len(b):
        return min(len(a), len(b))
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    return None
