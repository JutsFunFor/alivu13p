"""The AXI Quad SPI controller, driven as a plain SPI master.

This is not the flash-programming path. It exists to ask the configuration flash what it
is -- a JEDEC ID read, opcode 0x9F, which every SPI flash ever made answers -- because
the part fitted to this board is not documented anywhere.

The controller sits behind STARTUPE3, so "the flash" here means the device the FPGA
booted from, reached over the dedicated configuration pins.
"""

from __future__ import annotations

import time

# Register offsets within the controller's window (PG153).
SRR      = 0x40   # write RESET_VALUE to reset the whole core
SPICR    = 0x60
SPISR    = 0x64
SPIDTR   = 0x68   # transmit FIFO
SPIDRR   = 0x6C   # receive FIFO
SPISSR   = 0x70   # slave select, active low
TX_OCY   = 0x74
RX_OCY   = 0x78

RESET_VALUE = 0x0000_000A

# Control register bits.
CR_LOOP      = 1 << 0
CR_SPE       = 1 << 1   # enable
CR_MASTER    = 1 << 2
CR_CPOL      = 1 << 3
CR_CPHA      = 1 << 4
CR_TX_RESET  = 1 << 5
CR_RX_RESET  = 1 << 6
CR_MANUAL_SS = 1 << 7
CR_INHIBIT   = 1 << 8   # hold off the transfer while the FIFO is loaded
CR_LSB_FIRST = 1 << 9

# Status register bits.
SR_RX_EMPTY = 1 << 0
SR_RX_FULL  = 1 << 1
SR_TX_EMPTY = 1 << 2
SR_TX_FULL  = 1 << 3
SR_MODF     = 1 << 4

# Flash opcodes used here. Read-only, every one of them.
RDID = 0x9F
RDSR = 0x05

# JEDEC manufacturer IDs seen on Xilinx configuration flash. Bank 0 of JEP106.
MANUFACTURERS = {
    0x01: "Spansion/Infineon",
    0x20: "Micron/Numonyx",
    0xC2: "Macronix",
    0xEF: "Winbond",
    0x9D: "ISSI",
    0x1F: "Atmel/Adesto",
    0x1C: "EON",
    0xBF: "SST",
}


class QuadSpi:
    """One AXI Quad SPI controller in standard SPI master mode."""

    def __init__(self, regs, base: int):
        self.regs = regs
        self.base = base

    def _read(self, offset: int) -> int:
        return self.regs.read32(self.base + offset)

    def _write(self, offset: int, value: int) -> None:
        self.regs.write32(self.base + offset, value)

    def reset(self) -> None:
        self._write(SRR, RESET_VALUE)
        # Enabled, master, manual slave select, both FIFOs cleared, transfer inhibited
        # so the FIFO can be loaded before anything appears on the wire.
        self._write(SPICR, CR_INHIBIT | CR_MANUAL_SS | CR_RX_RESET | CR_TX_RESET
                    | CR_MASTER | CR_SPE)
        self._write(SPISSR, 0xFFFF_FFFF)   # nothing selected

    def transfer(self, out: bytes, timeout: float = 1.0) -> bytes:
        """Clock len(out) bytes out and return the len(out) bytes clocked in.

        SPI is inherently full duplex: a read is a write of don't-care bytes, and the
        response to byte n arrives while byte n+1 goes out. The caller does that
        bookkeeping, because only the caller knows the command's shape.
        """
        if not 0 < len(out) <= 16:
            raise ValueError(f"{len(out)} bytes does not fit the 16-deep FIFO")
        self._write(SPICR, CR_INHIBIT | CR_MANUAL_SS | CR_RX_RESET | CR_TX_RESET
                    | CR_MASTER | CR_SPE)
        self._write(SPISSR, 0xFFFF_FFFE)   # select slave 0
        for byte in out:
            self._write(SPIDTR, byte)
        # Releasing the inhibit is what starts the clock.
        self._write(SPICR, CR_MANUAL_SS | CR_MASTER | CR_SPE)
        deadline = time.monotonic() + timeout
        while not self._read(SPISR) & SR_TX_EMPTY:
            if time.monotonic() > deadline:
                self._write(SPICR, CR_INHIBIT | CR_MANUAL_SS | CR_MASTER | CR_SPE)
                self._write(SPISSR, 0xFFFF_FFFF)
                raise TimeoutError(f"SPI transfer did not complete; SR={self._read(SPISR):#06x}")
        self._write(SPICR, CR_INHIBIT | CR_MANUAL_SS | CR_MASTER | CR_SPE)
        self._write(SPISSR, 0xFFFF_FFFF)   # deselect, which ends the command
        got = bytearray()
        while not self._read(SPISR) & SR_RX_EMPTY:
            got.append(self._read(SPIDRR) & 0xFF)
            if len(got) > len(out):
                raise RuntimeError("receive FIFO returned more bytes than were sent")
        return bytes(got)

    def jedec_id(self) -> tuple[int, int, int]:
        """(manufacturer, memory type, capacity) from opcode 0x9F."""
        got = self.transfer(bytes([RDID, 0, 0, 0]))
        if len(got) != 4:
            raise RuntimeError(f"expected 4 bytes back from RDID, got {len(got)}")
        # Byte 0 was clocked in while the opcode was going out, so it carries nothing.
        return got[1], got[2], got[3]

    def status(self) -> int:
        """The flash's own status register, opcode 0x05."""
        return self.transfer(bytes([RDSR, 0]))[1]


def describe_flash(manufacturer: int, memory_type: int, capacity: int) -> str:
    """A human-readable line for a JEDEC ID triple.

    Capacity is log2 of the size in bytes for nearly every vendor, so 0x18 is 16 MiB.
    That convention is not universal, which is why the raw bytes are printed too.
    """
    name = MANUFACTURERS.get(manufacturer, f"unknown manufacturer {manufacturer:#04x}")
    size = f", {1 << (capacity - 20)} MiB" if 20 <= capacity <= 32 else ""
    return (f"{name}, type {memory_type:#04x}, capacity {capacity:#04x}{size} "
            f"(raw {manufacturer:02X} {memory_type:02X} {capacity:02X})")
