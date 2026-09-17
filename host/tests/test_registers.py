"""Register access over the BAR."""

import pytest

from alivu13p import GPIO_DATA1, GOLDEN_PCIE

pytestmark = pytest.mark.hardware

GPIO = GOLDEN_PCIE["gpio"].base


def test_gpio_data_register_is_writable(axil):
    """Exercise every implemented data bit and restore the original LED value.

    C_ALL_OUTPUTS=1 fixes the direction at synthesis time. The generated GPIO
    read mux returns all ones for TRI, so TRI is not a writable-register test.
    DATA readback still proves changing values traverse the BAR in both directions.
    """
    original = axil.read32(GPIO + GPIO_DATA1)
    try:
        for pattern in (0xFF, 0x00, 0xA5, 0x5A):
            axil.write32(GPIO + GPIO_DATA1, pattern)
            assert axil.read32(GPIO + GPIO_DATA1) & 0xFF == pattern
    finally:
        axil.write32(GPIO + GPIO_DATA1, original)


def test_led_walk(axil):
    """Walk a single bit across the eight LEDs and read it back each time.

    Reading back catches a stuck bit in the register. It cannot catch a swapped or dead
    LED, which needs eyes on the card -- run this and watch.
    """
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
