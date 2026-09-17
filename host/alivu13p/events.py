"""User interrupts from the card.

Each user interrupt is a file that blocks until the interrupt arrives. Waiting on it
with poll() rather than a blocking read is what makes a timeout possible -- and a
timeout is the whole point, because the failure being tested for is the interrupt never
arriving.
"""

from __future__ import annotations

import os
import select


class Event:
    def __init__(self, index: int = 0, event: int = 0):
        self.path = f"/dev/xdma{index}_events_{event}"
        self._fd = os.open(self.path, os.O_RDONLY)

    def close(self) -> None:
        os.close(self._fd)

    def __enter__(self) -> "Event":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def wait(self, timeout_s: float = 2.0) -> bool:
        """True if the interrupt arrived within the timeout."""
        poller = select.poll()
        poller.register(self._fd, select.POLLIN)
        if not poller.poll(timeout_s * 1000):
            return False
        os.read(self._fd, 4)
        return True
