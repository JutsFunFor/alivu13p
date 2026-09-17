"""Register access over the BAR."""

import pytest

from alivu13p import GPIO_DATA1, GPIO_DATA2, GPIO_TRI1, GPIO_TRI2, GOLDEN_PCIE

pytestmark = pytest.mark.hardware

GPIO = GOLDEN_PCIE["gpio"].base


def test_gpio_direction_registers_are_writable(axil):
    """The tri-state registers are plain read/write, so they prove the path both ways.

    Done before anything else because it separates "the BAR works" from "the peripheral
    behind it works". A GPIO data register on an all-outputs port reads back what was
    written, but so does an unmapped address that floats -- the direction register is a
    real register with no side effects, which makes it the honest first test.
    """
    original = axil.read32(GPIO + GPIO_TRI1)
    try:
        for pattern in (0x0000_00FF, 0x0000_0000, 0x0000_00A5):
            axil.write32(GPIO + GPIO_TRI1, pattern)
            assert axil.read32(GPIO + GPIO_TRI1) == pattern
    finally:
        axil.write32(GPIO + GPIO_TRI1, original)


def test_led_walk(axil):
    """Walk a single bit across the eight LEDs and read it back each time.

    Reading back catches a stuck bit in the register. It cannot catch a swapped or dead
    LED, which needs eyes on the card -- run this and watch.
    """
    axil.write32(GPIO + GPIO_TRI1, 0x0000_0000)   # all outputs
    for bit in range(8):
        axil.write32(GPIO + GPIO_DATA1, 1 << bit)
        assert axil.read32(GPIO + GPIO_DATA1) & 0xFF == 1 << bit
    axil.write32(GPIO + GPIO_DATA1, 0x0000_00FF)


def test_unaligned_access_is_refused(axil):
    """The wrapper refuses what the fabric cannot do, rather than letting the CPU split it."""
    with pytest.raises(ValueError):
        axil.read32(GPIO + 1)
    with pytest.raises(ValueError):
        axil.write32(GPIO + 2, 0)
