"""Register access over the XDMA AXI-Lite BAR.

The driver exposes the BAR as /dev/xdma0_user, which is mmap-able, so a register access
is a memory access and there is no ioctl layer to get wrong.
"""

from __future__ import annotations

import mmap
import os
import struct


class AxiLite:
    """Memory-mapped register window.

    Reads and writes are 32 bits and must be 4-byte aligned. That is not a convenience
    restriction: the AXI-Lite fabric behind this BAR has a 32-bit data path, and an
    unaligned or wider access is split by the CPU into pieces that reach the fabric as
    separate transactions -- which for a register with side effects is a different
    operation from the one intended.
    """

    def __init__(self, path: str = "/dev/xdma0_user", size: int = 0x8_0000):
        self.path = path
        self.size = size
        self._fd = os.open(path, os.O_RDWR | os.O_SYNC)
        try:
            self._map = mmap.mmap(self._fd, size, mmap.MAP_SHARED,
                                  mmap.PROT_READ | mmap.PROT_WRITE)
        except Exception:
            os.close(self._fd)
            raise

    def close(self) -> None:
        self._map.close()
        os.close(self._fd)

    def __enter__(self) -> "AxiLite":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def _check(self, addr: int) -> None:
        if addr % 4:
            raise ValueError(f"address 0x{addr:X} is not 4-byte aligned")
        if not 0 <= addr <= self.size - 4:
            raise ValueError(f"address 0x{addr:X} is outside the {self.size}-byte window")

    def read32(self, addr: int) -> int:
        self._check(addr)
        return struct.unpack_from("<I", self._map, addr)[0]

    def write32(self, addr: int, value: int) -> None:
        self._check(addr)
        if not 0 <= value <= 0xFFFF_FFFF:
            raise ValueError(f"value 0x{value:X} does not fit in 32 bits")
        struct.pack_into("<I", self._map, addr, value)
