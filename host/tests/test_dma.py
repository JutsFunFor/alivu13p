"""Bulk transfer to and from the card's on-chip memories."""

import os

import pytest

from alivu13p import GOLDEN_PCIE, first_difference

pytestmark = pytest.mark.hardware

# Both DMA windows, so BRAM and URAM get the identical treatment. They are the same size
# and shape in the design precisely so that this can be one parametrised test: a
# difference in the result is then a property of the memory, not of the test.
WINDOWS = [w.name for w in GOLDEN_PCIE.of_kind("dma")]


def _report(window, offset, wrote, read):
    """Describe a mismatch in terms of what it implies, not just that it happened."""
    bad = first_difference(wrote, read)
    if bad is None:
        return None
    return (
        f"{window} mismatch at byte {bad} of {len(wrote)} "
        f"(card address 0x{offset + bad:08X}): "
        f"wrote {wrote[bad]:#04x}, read {read[bad]:#04x}. "
        f"Offset is {'a multiple of 64' if bad % 64 == 0 else f'{bad % 64} past a 64-byte boundary'}, "
        f"which points at {'a whole AXI word' if bad % 64 == 0 else 'a byte lane'}."
    )


@pytest.mark.parametrize("name", WINDOWS)
def test_roundtrip_random(dma, name):
    """Write random data over the whole window and read it back.

    Random rather than a fixed pattern: a stuck bit, a repeated word and an aliased
    address all survive a constant pattern, and two of the three survive a counting one.
    """
    window = GOLDEN_PCIE[name]
    payload = os.urandom(window.size)

    wr = dma.write(window.base, payload)
    assert wr.nbytes == window.size

    got, rd = dma.read(window.base, window.size)
    assert len(got) == window.size

    problem = _report(name, window.base, payload, got)
    assert problem is None, problem

    print(f"\n{name}: write {wr.gbytes_per_s:.2f} GB/s, read {rd.gbytes_per_s:.2f} GB/s "
          f"({window.size} bytes)")


@pytest.mark.parametrize("name", WINDOWS)
def test_windows_are_independent(dma, name):
    """Writing one window must not disturb the other.

    This is the test that catches an address decode that is too narrow -- a crossbar
    range one bit short maps both memories onto the same place, and every single-window
    test still passes.
    """
    windows = GOLDEN_PCIE.of_kind("dma")
    if len(windows) < 2:
        pytest.skip("needs at least two DMA windows")

    this = GOLDEN_PCIE[name]
    others = [w for w in windows if w.name != name]

    marker = b"\xA5" * 4096
    for w in windows:
        dma.write(w.base, bytes(4096))
    dma.write(this.base, marker)

    got, _ = dma.read(this.base, 4096)
    assert got == marker, f"{name} did not keep its own data"

    for other in others:
        got, _ = dma.read(other.base, 4096)
        assert got == bytes(4096), (
            f"writing {name} at 0x{this.base:08X} changed {other.name} at "
            f"0x{other.base:08X} -- the two windows overlap, so the address decode is wrong"
        )


@pytest.mark.parametrize("name", WINDOWS)
def test_unaligned_offsets(dma, name):
    """Transfers that do not start or end on an AXI word boundary.

    The DMA engine has to split these into partial beats with byte strobes, which is a
    different path through the hardware from the aligned case and a common place for a
    memory controller to be wrong.
    """
    window = GOLDEN_PCIE[name]
    for offset, length in ((1, 63), (63, 130), (7, 4097)):
        payload = os.urandom(length)
        dma.write(window.base + offset, payload)
        got, _ = dma.read(window.base + offset, length)
        problem = _report(f"{name}[+{offset},{length}]", window.base + offset, payload, got)
        assert problem is None, problem
