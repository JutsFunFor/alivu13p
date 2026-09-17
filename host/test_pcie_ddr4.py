#!/usr/bin/env python3
"""Destructive memory qualification for designs/04_pcie_ddr4 only.

Run with --full to write then verify every byte of channel 1's 4 GiB aperture.
A design identity check precedes any DMA. No hardware means failure, not skip.
"""
import argparse
import os
import random
import time

from alivu13p import AxiLite, Dma

STATUS = 0x30008
SIZE = 1 << 32
BLOCK = 4 << 20


def check_status(regs):
    value = regs.read32(STATUS)
    if value >> 8 != 0xD40101:
        raise RuntimeError(f"Wrong design ID: {value:#010x}; expected 04_pcie_ddr4")
    if value & 15 != 5:
        raise RuntimeError(f"DDR4 not calibrated or ECC event latched: {value:#010x}")


def payload(address, size):
    # Independent deterministic streams per address; full write before full read
    # detects aliased high address bits as well as within-block data corruption.
    return random.Random(address ^ 0xA11D_D4A4).randbytes(size)


def verify(dma, address, expected):
    actual, _ = dma.read(address, len(expected))
    if actual != expected:
        first = next(i for i, (a, b) in enumerate(zip(actual, expected)) if a != b)
        raise AssertionError(f"DDR4 mismatch at {address + first:#010x}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full', action='store_true', help='destructively test all 4 GiB')
    args = parser.parse_args()
    with AxiLite() as regs, Dma() as dma:
        deadline = time.monotonic() + 30
        while True:
            value = regs.read32(STATUS)
            if value >> 8 != 0xD40101:
                raise RuntimeError(f"Wrong design: {value:#010x}")
            if value & 5 == 5:
                break
            if time.monotonic() > deadline:
                raise TimeoutError('DDR4 calibration did not complete')
            time.sleep(0.1)
        check_status(regs)
        # Probe all high address bits and the very end of the aperture.
        addresses = sorted({0, SIZE - 4096} | {1 << bit for bit in range(12, 32)})
        for address in addresses:
            dma.write(address, payload(address, 4096))
        for address in addresses:
            verify(dma, address, payload(address, 4096))
        print(f'PASS: {len(addresses)} distinct sparse 4 KiB windows', flush=True)
        # Guard bytes detect writes that incorrectly ignore WSTRB under ECC RMW.
        for offset, length in ((1, 1), (7, 63), (63, 130), (4093, 4097)):
            base = 0x100000
            expected = bytearray(os.urandom(16384))
            dma.write(base, expected)
            fragment = os.urandom(length)
            dma.write(base + offset, fragment)
            expected[offset:offset + length] = fragment
            verify(dma, base, expected)
        print('PASS: unaligned writes preserve surrounding bytes', flush=True)
        count = SIZE if args.full else 64 << 20
        started = time.monotonic()
        for phase in ('write', 'read'):
            for address in range(0, count, BLOCK):
                data = payload(address, BLOCK)
                if phase == 'write':
                    dma.write(address, data)
                else:
                    verify(dma, address, data)
                if (address + BLOCK) % (256 << 20) == 0:
                    print(f'{phase}: {(address + BLOCK) >> 20} MiB', flush=True)
            check_status(regs)
        print(f'PASS: {count} bytes written then verified; '
              f'{time.monotonic() - started:.2f}s including data generation; no ECC events', flush=True)


if __name__ == '__main__':
    main()
