#!/usr/bin/env python3
"""Board inventory for designs/06_board_mgmt only.

Reads the two things about this board that nothing else here can tell you:

  * which SPI flash it boots from, by JEDEC ID;
  * what is plugged into each QSFP cage, by SFF-8636 EEPROM.

Both are read-only. Nothing in this script writes to the flash or to a module.

An empty cage is not a failure -- it is the expected state for a board with one cable.
What is a failure is a cage that reports a module present and then will not talk, or a
flash that answers with all ones or all zeros, because either means the interface is
wired to the wrong pins.
"""
import argparse
import sys

from alivu13p import (BOARD_MGMT, GPIO_DATA1, GPIO_DATA2, AxiLite, I2cError, Iic,
                      QSFP_ADDR, QuadSpi, describe_flash, describe_module)

IDENTITY = 0x424D_0101          # "BM", revision 1, End Of Startup asserted
IDENTITY_MASK = 0xFFFF_FF00

# Sideband GPIO bit assignments, matching the top-level comment in the RTL.
OUT_RESETL0, OUT_LPMODE0, OUT_RESETL1, OUT_LPMODE1 = 1 << 0, 1 << 1, 1 << 2, 1 << 3
IN_MODPRSL0, IN_INTL0, IN_MODPRSL1, IN_INTL1 = 1 << 0, 1 << 1, 1 << 2, 1 << 3


def check_identity(regs) -> None:
    gpio = BOARD_MGMT["gpio"].base
    value = regs.read32(gpio + GPIO_DATA2)
    if value & IDENTITY_MASK != IDENTITY & IDENTITY_MASK:
        raise RuntimeError(
            f"Wrong design: identity {value:#010x}; expected {IDENTITY:#010x} "
            f"(06_board_mgmt). Program board_mgmt.bit first.")
    if not value & 1:
        raise RuntimeError("End Of Startup is low, so the SPI controller's STARTUPE3 "
                           "is not reporting a configured device")
    print(f"PASS identity: {value:#010x}", flush=True)


def report_flash(regs) -> None:
    spi = QuadSpi(regs, BOARD_MGMT["qspi"].base)
    spi.reset()
    manufacturer, memory_type, capacity = spi.jedec_id()
    raw = (manufacturer, memory_type, capacity)
    if raw in {(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF)}:
        raise AssertionError(
            f"flash JEDEC ID reads {manufacturer:02X} {memory_type:02X} {capacity:02X}: "
            "an idle bus, not a device. The controller reached no flash.")
    print(f"PASS flash: {describe_flash(*raw)}", flush=True)
    print(f"     flash status register: {spi.status():#04x}", flush=True)


def report_cage(regs, cage: int, present: bool) -> bool:
    """Read one cage's module EEPROM. Returns True if a module answered."""
    iic = Iic(regs, BOARD_MGMT[f"iic{cage}"].base)
    iic.reset()
    if not present:
        # Prove the bus is silent rather than assuming it: a cage reported empty that
        # still answers would mean ModPrsL is not the pin we think it is.
        if iic.responds(QSFP_ADDR):
            raise AssertionError(
                f"cage {cage} reports no module, but something answers at "
                f"{QSFP_ADDR:#04x} -- ModPrsL and the I2C bus disagree")
        print(f"     cage {cage}: empty, bus silent", flush=True)
        return False
    try:
        page = iic.read_bytes(QSFP_ADDR, 128, 128)   # upper page 0: identity fields
    except I2cError as error:
        raise AssertionError(
            f"cage {cage} reports a module present, but its EEPROM did not "
            f"respond: {error}") from None
    if set(page) <= {0x00} or set(page) <= {0xFF}:
        raise AssertionError(
            f"cage {cage} EEPROM reads all {page[0]:#04x} -- the bus acknowledged but "
            "returned nothing, which is what a wrong pin pair looks like")
    info = describe_module(page)
    print(f"PASS cage {cage}: {info['identifier']}, {info['connector']}", flush=True)
    print(f"     vendor {info['vendor']!r} part {info['part']!r} "
          f"rev {info['revision']!r}", flush=True)
    if "serial" in info:
        print(f"     serial {info['serial']!r} date {info['date']!r}", flush=True)
    if "copper_length_m" in info:
        print(f"     copper cable, {info['copper_length_m']} m", flush=True)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--leds', action='store_true',
                        help='walk a bit across the eight user LEDs, for a human to watch')
    args = parser.parse_args()
    with AxiLite() as regs:
        check_identity(regs)
        report_flash(regs)

        qsfp = BOARD_MGMT["qsfp"].base
        control = regs.read32(qsfp + GPIO_DATA1)
        status = regs.read32(qsfp + GPIO_DATA2)
        # ResetL is active low, so both bits must read high for the modules to be out of
        # reset. This is the state the design powers up in, with no host involvement.
        if control & (OUT_RESETL0 | OUT_RESETL1) != (OUT_RESETL0 | OUT_RESETL1):
            raise AssertionError(
                f"sideband control reads {control:#04x}: a ResetL is low, so a module "
                "is being held in reset")
        if control & (OUT_LPMODE0 | OUT_LPMODE1):
            raise AssertionError(f"sideband control reads {control:#04x}: LPMode is "
                                 "asserted, which throttles an optical module")
        print(f"PASS sideband: control {control:#04x} (both ResetL high, LPMode low), "
              f"status {status:#04x}", flush=True)

        # ModPrsL is active low: a zero means a module is seated.
        cage0 = not status & IN_MODPRSL0
        cage1 = not status & IN_MODPRSL1
        found = sum(report_cage(regs, cage, present)
                    for cage, present in ((0, cage0), (1, cage1)))
        if not found:
            print("NOTE: no module in either cage, so the I2C path is untested. "
                  "Plug in the DAC and run again.", flush=True)

        if args.leds:
            import time
            gpio = BOARD_MGMT["gpio"].base
            for step in range(16):
                regs.write32(gpio + GPIO_DATA1, 1 << (step % 8))
                time.sleep(0.25)
            regs.write32(gpio + GPIO_DATA1, 0)
            print("PASS leds: walked one bit twice across all eight", flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
