#!/usr/bin/env python3
"""Packet and backpressure qualification for designs/05_pcie_stream only.

C2H is opened with O_TRUNC: in XDMA this selects end-of-packet flush, not a
filesystem operation. DMA buffers use anonymous mmap for page alignment.
"""
import concurrent.futures
import ctypes
import mmap
import os
import random
import time

from alivu13p import AxiLite


def main():
    with AxiLite() as regs:
        identity = regs.read32(0x30008)
        if identity != 0x53540101:
            raise RuntimeError(f'Wrong design: {identity:#010x}; expected 05_pcie_stream')
    # Use the synchronous read path with a page-aligned destination. Python's
    # os.read allocates its own buffer; readv selects the driver's separate AIO path.
    libc = ctypes.CDLL(None, use_errno=True)
    libc.read.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_size_t]
    libc.read.restype = ctypes.c_ssize_t
    h2c = os.open('/dev/xdma0_h2c_0', os.O_WRONLY)
    c2h = os.open('/dev/xdma0_c2h_0', os.O_RDONLY | os.O_TRUNC)
    # Request extra receive capacity so returning exactly the packet's length
    # checks TLAST/EOP, rather than merely satisfying an exact-sized descriptor.
    capacity = (4 << 20) + 4096
    rng = random.Random(0x53540101)
    sizes = [1, 7, 63, 64, 65, 127, 4095, 4096, 4097, 65535, 65536,
             65537, 1 << 20, (4 << 20) - 17]
    sizes += [rng.randrange(1, 256 << 10) for _ in range(50)]
    transferred = 0
    try:
        with mmap.mmap(-1, capacity) as tx, mmap.mmap(-1, capacity) as rx:
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                for number, size in enumerate(sizes):
                    data = rng.randbytes(size)
                    tx[:size] = data
                    rx[:] = b'\xA5' * capacity
                    # H2C starts first; packets above FIFO capacity force backpressure
                    # until the deliberately delayed C2H request drains the FIFO.
                    future = pool.submit(os.write, h2c, memoryview(tx)[:size])
                    time.sleep(0.02 if size > 65536 else 0.001)
                    pointer = ctypes.addressof(ctypes.c_char.from_buffer(rx))
                    got = libc.read(c2h, pointer, capacity)
                    if got < 0:
                        error = ctypes.get_errno()
                        raise OSError(error, os.strerror(error))
                    written = future.result(timeout=15)
                    if written != size or got != size:
                        raise AssertionError(f'packet {number}: requested={size} written={written} received={got}')
                    if rx[:got] != data:
                        raise AssertionError(f'packet {number}: payload mismatch, {size} bytes')
                    transferred += size
                    print(f'PASS packet {number:02d}: {size} bytes', flush=True)
    finally:
        os.close(c2h)
        os.close(h2c)
    print(f'PASS: {len(sizes)} packets, {transferred} bytes, exact packet lengths and payloads', flush=True)


if __name__ == '__main__':
    main()
