"""The AXI IIC controller, and just enough SFF-8636 to identify a QSFP module.

A module's EEPROM is the only thing on the board that will tell you what is plugged into
a cage. Reading it is also the cheapest proof that the cage's I2C pins are the pins this
repository claims they are: a wrong pin returns 0xFF forever, a right one returns ASCII.

The controller is driven in dynamic mode, where the direction and the start/stop bits
travel through the transmit FIFO alongside the data, so one combined write-then-read
transaction is four FIFO writes.
"""

from __future__ import annotations

import time

# Register offsets within the controller's window (PG090).
GIE          = 0x01C
ISR          = 0x020
IER          = 0x028
SOFTR        = 0x040
CR           = 0x100
SR           = 0x104
TX_FIFO      = 0x108
RX_FIFO      = 0x10C
ADR          = 0x110
TX_FIFO_OCY  = 0x114
RX_FIFO_OCY  = 0x118
TEN_ADR      = 0x11C
RX_FIFO_PIRQ = 0x120

RESET_VALUE = 0x0000_000A

# Control register bits.
CR_EN            = 1 << 0
CR_TX_FIFO_RESET = 1 << 1
CR_MSMS          = 1 << 2
CR_TX            = 1 << 3
CR_TXAK          = 1 << 4
CR_RSTA          = 1 << 5

# Status register bits.
SR_ABGC        = 1 << 0
SR_AAS         = 1 << 1
SR_BB          = 1 << 2   # bus busy
SR_SRW         = 1 << 3
SR_TX_FIFO_FULL = 1 << 4
SR_RX_FIFO_FULL = 1 << 5
SR_RX_FIFO_EMPTY = 1 << 6
SR_TX_FIFO_EMPTY = 1 << 7

# Transmit FIFO tag bits: which byte of a transaction this is.
FIFO_START = 1 << 8
FIFO_STOP  = 1 << 9

FIFO_DEPTH = 16

# Every QSFP module answers at this 7-bit address; it is fixed by SFF-8636.
QSFP_ADDR = 0x50


class I2cError(RuntimeError):
    """A transaction did not complete -- usually because nothing answered."""


class Iic:
    """One AXI IIC controller."""

    def __init__(self, regs, base: int):
        self.regs = regs
        self.base = base

    def _read(self, offset: int) -> int:
        return self.regs.read32(self.base + offset)

    def _write(self, offset: int, value: int) -> None:
        self.regs.write32(self.base + offset, value)

    def reset(self) -> None:
        self._write(SOFTR, RESET_VALUE)
        time.sleep(0.001)
        self._write(CR, CR_TX_FIFO_RESET)
        self._write(CR, CR_EN)
        self._write(RX_FIFO_PIRQ, FIFO_DEPTH - 1)

    def _wait_idle(self, timeout: float) -> None:
        deadline = time.monotonic() + timeout
        while self._read(SR) & SR_BB:
            if time.monotonic() > deadline:
                raise I2cError(f"bus stayed busy; SR={self._read(SR):#06x}")

    def read(self, device: int, offset: int, count: int, timeout: float = 0.5) -> bytes:
        """Random read: write the byte address, repeated start, then read `count` bytes.

        `count` is capped at the receive FIFO depth. Reading more than that needs the
        programmable interrupt threshold to be managed mid-transaction, which buys
        nothing here -- an EEPROM page is read in chunks either way.
        """
        if not 0 < count <= FIFO_DEPTH:
            raise ValueError(f"count must be 1..{FIFO_DEPTH}, not {count}")
        self.reset()
        self._wait_idle(timeout)
        self._write(TX_FIFO, FIFO_START | (device << 1))      # address, writing
        self._write(TX_FIFO, offset & 0xFF)                   # the byte address
        self._write(TX_FIFO, FIFO_START | (device << 1) | 1)  # repeated start, reading
        self._write(TX_FIFO, FIFO_STOP | count)               # how many, then stop
        got = bytearray()
        deadline = time.monotonic() + timeout
        while len(got) < count:
            if not self._read(SR) & SR_RX_FIFO_EMPTY:
                got.append(self._read(RX_FIFO) & 0xFF)
                continue
            if time.monotonic() > deadline:
                raise I2cError(
                    f"read of {count} bytes from {device:#04x}+{offset:#04x} returned "
                    f"{len(got)}; SR={self._read(SR):#06x}")
        return bytes(got)

    def read_bytes(self, device: int, offset: int, count: int) -> bytes:
        """The same, in FIFO-sized chunks, for reads longer than the FIFO."""
        out = bytearray()
        while len(out) < count:
            chunk = min(FIFO_DEPTH, count - len(out))
            out += self.read(device, offset + len(out), chunk)
        return bytes(out)

    def responds(self, device: int, timeout: float = 0.1) -> bool:
        """Whether anything acknowledges at this address."""
        try:
            self.read(device, 0, 1, timeout=timeout)
            return True
        except I2cError:
            return False


# ------------------------------------------------------------------------ SFF-8636
#
# Byte offsets in the module's upper page 0. Only the identity fields are decoded; the
# diagnostics need per-vendor interpretation and a module that supports them.
IDENTIFIER   = 128
EXT_ID       = 129
CONNECTOR    = 130
LENGTH_COPPER = 146
VENDOR_NAME  = (148, 16)
VENDOR_OUI   = (165, 3)
VENDOR_PN    = (168, 16)
VENDOR_REV   = (184, 2)
VENDOR_SN    = (196, 16)
DATE_CODE    = (212, 8)

IDENTIFIERS = {
    0x00: "unspecified", 0x03: "SFP/SFP+/SFP28", 0x0C: "QSFP",
    0x0D: "QSFP+", 0x11: "QSFP28", 0x12: "CXP2", 0x18: "QSFP-DD",
}

CONNECTORS = {
    0x01: "SC", 0x07: "LC", 0x0B: "optical pigtail", 0x0C: "MPO 1x12",
    0x21: "copper pigtail", 0x22: "RJ45", 0x23: "no separable connector",
    0x24: "MXC 2x16",
}


def _text(raw: bytes, field: tuple[int, int], origin: int = 128) -> str:
    start, length = field
    piece = raw[start - origin:start - origin + length]
    return piece.decode("ascii", errors="replace").strip()


def describe_module(page: bytes, origin: int = 128) -> dict:
    """Decode the identity fields of SFF-8636 upper page 0.

    `page` starts at byte `origin` of the module's address space, so passing the 64 bytes
    from 128 onwards is enough for everything except the serial number.
    """
    def byte(n: int) -> int:
        index = n - origin
        return page[index] if 0 <= index < len(page) else -1

    identifier = byte(IDENTIFIER)
    connector = byte(CONNECTOR)
    out = {
        "identifier": IDENTIFIERS.get(identifier, f"unknown {identifier:#04x}"),
        "identifier_raw": identifier,
        "connector": CONNECTORS.get(connector, f"unknown {connector:#04x}"),
        "vendor": _text(page, VENDOR_NAME, origin),
        "part": _text(page, VENDOR_PN, origin),
        "revision": _text(page, VENDOR_REV, origin),
    }
    if len(page) >= VENDOR_SN[0] - origin + VENDOR_SN[1]:
        out["serial"] = _text(page, VENDOR_SN, origin)
        out["date"] = _text(page, DATE_CODE, origin)
    length = byte(LENGTH_COPPER)
    if length > 0:
        out["copper_length_m"] = length
    return out
