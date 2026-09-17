"""The flash and module drivers, checked against models of the two controllers.

These need no card. The point is the part that hardware cannot check for you: whether
the register sequence this code emits is the sequence the IP documents. A driver that
talks to real silicon and gets nothing back cannot tell you whether the bus is wrong or
the sequence is -- so the sequence is pinned down here, where the answer is unambiguous.

The models are deliberately strict. They fail on anything the IP would treat as a
protocol error, so a driver change that happens to still work on one particular flash
does not pass quietly.
"""

import pytest

from alivu13p import QSFP_ADDR, I2cError, Iic, QuadSpi, describe_flash, describe_module
from alivu13p import i2c as i2c_mod
from alivu13p import qspi as qspi_mod


class FakeFlash:
    """An SPI flash that answers RDID and RDSR and nothing else."""

    def __init__(self, jedec=(0x20, 0xBB, 0x19), status=0x00):
        self.jedec = bytes(jedec)
        self.status = status
        self.commands = []

    def exchange(self, out: bytes) -> bytes:
        self.commands.append(bytes(out))
        opcode = out[0]
        if opcode == qspi_mod.RDID:
            # Byte 0 is clocked in while the opcode goes out and carries nothing.
            body = b"\x00" + self.jedec
            return body[:len(out)].ljust(len(out), b"\x00")
        if opcode == qspi_mod.RDSR:
            return (b"\x00" + bytes([self.status]))[:len(out)].ljust(len(out), b"\x00")
        raise AssertionError(f"unexpected opcode {opcode:#04x}")


class QuadSpiModel:
    """Enough of the AXI Quad SPI register interface to catch a wrong sequence."""

    def __init__(self, base: int, flash: FakeFlash):
        self.base = base
        self.flash = flash
        self.cr = 0
        self.ssr = 0xFFFFFFFF
        self.tx = bytearray()
        self.rx = bytearray()
        self.resets = 0

    def owns(self, addr: int) -> bool:
        return self.base <= addr < self.base + 0x1000

    def write32(self, addr: int, value: int) -> None:
        offset = addr - self.base
        if offset == qspi_mod.SRR:
            assert value == qspi_mod.RESET_VALUE, "SRR takes one magic value"
            self.resets += 1
            self.cr, self.ssr = 0, 0xFFFFFFFF
            self.tx.clear()
            self.rx.clear()
        elif offset == qspi_mod.SPICR:
            was_inhibited = bool(self.cr & qspi_mod.CR_INHIBIT)
            if value & qspi_mod.CR_TX_RESET:
                self.tx.clear()
            if value & qspi_mod.CR_RX_RESET:
                self.rx.clear()
            self.cr = value
            releasing = was_inhibited and not value & qspi_mod.CR_INHIBIT
            if releasing:
                assert value & qspi_mod.CR_SPE, "transfer started with the core disabled"
                assert value & qspi_mod.CR_MASTER, "transfer started in slave mode"
                assert self.ssr != 0xFFFFFFFF, "transfer started with no slave selected"
                assert self.tx, "transfer started with an empty transmit FIFO"
                self.rx += self.flash.exchange(bytes(self.tx))
                self.tx.clear()
        elif offset == qspi_mod.SPISSR:
            self.ssr = value
        elif offset == qspi_mod.SPIDTR:
            assert self.cr & qspi_mod.CR_INHIBIT, "FIFO loaded while the clock was running"
            assert len(self.tx) < 16, "transmit FIFO overrun"
            self.tx.append(value & 0xFF)
        else:
            raise AssertionError(f"write to unmodelled SPI offset {offset:#05x}")

    def read32(self, addr: int) -> int:
        offset = addr - self.base
        if offset == qspi_mod.SPISR:
            status = 0
            if not self.rx:
                status |= qspi_mod.SR_RX_EMPTY
            if not self.tx:
                status |= qspi_mod.SR_TX_EMPTY
            return status
        if offset == qspi_mod.SPIDRR:
            assert self.rx, "read from an empty receive FIFO"
            return self.rx.pop(0)
        if offset == qspi_mod.SPICR:
            return self.cr
        raise AssertionError(f"read from unmodelled SPI offset {offset:#05x}")


class FakeEeprom:
    """An I2C EEPROM with an 8-bit internal address pointer."""

    def __init__(self, contents: bytes, address: int = QSFP_ADDR):
        self.contents = bytes(contents).ljust(256, b"\x00")
        self.address = address
        self.pointer = 0


class IicModel:
    """Enough of the AXI IIC dynamic-mode interface to catch a wrong sequence."""

    def __init__(self, base: int, devices):
        self.base = base
        self.devices = {d.address: d for d in devices}
        self.cr = 0
        self.enabled = False
        self.rx = bytearray()
        self.phase = "idle"
        self.target = None

    def owns(self, addr: int) -> bool:
        return self.base <= addr < self.base + 0x1000

    def write32(self, addr: int, value: int) -> None:
        offset = addr - self.base
        if offset == i2c_mod.SOFTR:
            assert value == i2c_mod.RESET_VALUE
            self.__init__(self.base, self.devices.values())
        elif offset == i2c_mod.CR:
            self.cr = value
            self.enabled = bool(value & i2c_mod.CR_EN)
        elif offset == i2c_mod.RX_FIFO_PIRQ:
            assert 0 <= value < i2c_mod.FIFO_DEPTH
        elif offset == i2c_mod.TX_FIFO:
            assert self.enabled, "FIFO written while the core was disabled"
            self._tx(value)
        else:
            raise AssertionError(f"write to unmodelled IIC offset {offset:#05x}")

    def _tx(self, word: int) -> None:
        start = bool(word & i2c_mod.FIFO_START)
        stop = bool(word & i2c_mod.FIFO_STOP)
        data = word & 0xFF
        if start:
            reading = bool(data & 1)
            device = self.devices.get(data >> 1)
            if device is None:
                self.phase = "nak"
                return
            self.target = device
            self.phase = "read" if reading else "write"
            return
        if self.phase == "nak":
            return
        if self.phase == "write":
            assert not stop, "a write byte carrying a stop bit ends the transaction early"
            self.target.pointer = data          # the byte address
            return
        if self.phase == "read":
            assert stop, "a dynamic read must carry the stop bit with its byte count"
            count = data
            for _ in range(count):
                self.rx.append(self.target.contents[self.target.pointer & 0xFF])
                self.target.pointer += 1
            self.phase = "idle"
            return
        raise AssertionError("data byte with no preceding start")

    def read32(self, addr: int) -> int:
        offset = addr - self.base
        if offset == i2c_mod.SR:
            status = 0
            if not self.rx:
                status |= i2c_mod.SR_RX_FIFO_EMPTY
            status |= i2c_mod.SR_TX_FIFO_EMPTY
            return status
        if offset == i2c_mod.RX_FIFO:
            assert self.rx, "read from an empty receive FIFO"
            return self.rx.pop(0)
        raise AssertionError(f"read from unmodelled IIC offset {offset:#05x}")


class FakeRegs:
    """An AxiLite work-alike that routes to whichever model owns the address."""

    def __init__(self, *models):
        self.models = models

    def _route(self, addr: int):
        for model in self.models:
            if model.owns(addr):
                return model
        raise AssertionError(f"no peripheral at {addr:#010x}")

    def read32(self, addr: int) -> int:
        assert addr % 4 == 0, "AXI-Lite access must be 4-byte aligned"
        return self._route(addr).read32(addr)

    def write32(self, addr: int, value: int) -> None:
        assert addr % 4 == 0, "AXI-Lite access must be 4-byte aligned"
        self._route(addr).write32(addr, value)


SFF_PAGE = bytearray(256)
SFF_PAGE[128] = 0x11                                     # QSFP28
SFF_PAGE[130] = 0x23                                     # no separable connector
SFF_PAGE[146] = 3                                        # 3 m of copper
SFF_PAGE[148:164] = b"ACME NETWORKS   "
SFF_PAGE[168:184] = b"QSFP28-DAC-3M   "
SFF_PAGE[184:186] = b"A1"
SFF_PAGE[196:212] = b"SN0123456789    "
SFF_PAGE[212:220] = b"250101  "


def test_jedec_id_sequence():
    flash = FakeFlash(jedec=(0x20, 0xBB, 0x19))
    model = QuadSpiModel(0x10000, flash)
    spi = QuadSpi(FakeRegs(model), 0x10000)
    spi.reset()
    assert spi.jedec_id() == (0x20, 0xBB, 0x19)
    assert flash.commands == [bytes([0x9F, 0, 0, 0])]
    assert model.ssr == 0xFFFFFFFF, "slave left selected after the command"


def test_flash_status_read():
    flash = FakeFlash(status=0x02)
    spi = QuadSpi(FakeRegs(QuadSpiModel(0x10000, flash)), 0x10000)
    spi.reset()
    assert spi.status() == 0x02


def test_transfer_rejects_more_than_the_fifo_holds():
    spi = QuadSpi(FakeRegs(QuadSpiModel(0x10000, FakeFlash())), 0x10000)
    spi.reset()
    with pytest.raises(ValueError):
        spi.transfer(bytes(17))


def test_describe_flash_decodes_capacity():
    line = describe_flash(0xC2, 0x20, 0x18)
    assert "Macronix" in line and "16 MiB" in line and "C2 20 18" in line


def test_eeprom_random_read():
    eeprom = FakeEeprom(SFF_PAGE)
    iic = Iic(FakeRegs(IicModel(0x50000, [eeprom])), 0x50000)
    assert iic.read(QSFP_ADDR, 148, 16) == b"ACME NETWORKS   "


def test_eeprom_long_read_is_chunked_not_truncated():
    eeprom = FakeEeprom(SFF_PAGE)
    iic = Iic(FakeRegs(IicModel(0x50000, [eeprom])), 0x50000)
    page = iic.read_bytes(QSFP_ADDR, 128, 128)
    assert len(page) == 128
    assert page == bytes(SFF_PAGE[128:256])


def test_absent_module_raises_rather_than_returning_zeros():
    iic = Iic(FakeRegs(IicModel(0x50000, [])), 0x50000)
    with pytest.raises(I2cError):
        iic.read(QSFP_ADDR, 0, 1, timeout=0.05)
    assert iic.responds(QSFP_ADDR, timeout=0.05) is False


def test_module_identity_decodes():
    eeprom = FakeEeprom(SFF_PAGE)
    iic = Iic(FakeRegs(IicModel(0x50000, [eeprom])), 0x50000)
    info = describe_module(iic.read_bytes(QSFP_ADDR, 128, 128))
    assert info["identifier"] == "QSFP28"
    assert info["vendor"] == "ACME NETWORKS"
    assert info["part"] == "QSFP28-DAC-3M"
    assert info["serial"] == "SN0123456789"
    assert info["copper_length_m"] == 3
