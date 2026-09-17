"""Host-side tools for the ALIVU13P.

Deliberately dependency-free: these run on a machine that has just had a driver
inserted, often over ssh, and requiring a virtualenv first is a poor trade for what
amounts to a few hundred lines of file I/O.
"""

from .axilite import AxiLite
from .dma import Dma, Transfer, first_difference
from .events import Event
from .i2c import QSFP_ADDR, I2cError, Iic, describe_module
from .memmap import (BOARD_MGMT, GOLDEN_PCIE, GPIO_DATA1, GPIO_DATA2, GPIO_TRI1,
                     GPIO_TRI2, Window)
from .qspi import QuadSpi, describe_flash

__all__ = [
    "AxiLite", "Dma", "Transfer", "first_difference", "Event",
    "Iic", "I2cError", "QSFP_ADDR", "describe_module",
    "QuadSpi", "describe_flash",
    "BOARD_MGMT", "GOLDEN_PCIE", "GPIO_DATA1", "GPIO_DATA2", "GPIO_TRI1", "GPIO_TRI2",
    "Window",
]
