"""The user interrupt path, end to end."""

import os

import pytest

from alivu13p import GPIO_DATA2, GPIO_TRI2, GOLDEN_PCIE

pytestmark = pytest.mark.hardware

GPIO = GOLDEN_PCIE["gpio"].base


@pytest.fixture
def event(require_card):
    from alivu13p import Event
    if not os.path.exists("/dev/xdma0_events_0"):
        pytest.skip("no user interrupt device: the design was built without one")
    with Event() as e:
        yield e


def test_host_triggered_interrupt(axil, event):
    """Raise an interrupt from the host and confirm it comes back.

    The card has no other way to generate one, which is the point: this tests the
    interrupt path itself rather than whatever might have raised it. usr_irq_req is a
    level, so it is asserted, waited on, and then cleared -- leaving it asserted would
    make every later test see a stale interrupt.
    """
    axil.write32(GPIO + GPIO_TRI2, 0)      # channel 2 is an output
    axil.write32(GPIO + GPIO_DATA2, 0)     # start deasserted
    try:
        axil.write32(GPIO + GPIO_DATA2, 1)
        assert event.wait(timeout_s=2.0), (
            "no interrupt within 2 s. The request reached the endpoint only if the GPIO "
            "write landed, so check the register read-back first; if that is fine, the "
            "endpoint is not forwarding user interrupts -- MSI may not be enabled."
        )
    finally:
        axil.write32(GPIO + GPIO_DATA2, 0)
