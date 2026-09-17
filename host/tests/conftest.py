import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def pytest_configure(config):
    config.addinivalue_line("markers", "hardware: needs a programmed, enumerated card")


@pytest.fixture(scope="session")
def require_card():
    """Skip rather than fail when there is no card.

    A missing card is not a test failure -- it means the suite was run somewhere it
    cannot say anything. Failing there would train people to ignore red results, which
    is worse than saying nothing.
    """
    if not os.path.exists("/dev/xdma0_user"):
        pytest.skip("/dev/xdma0_user is absent: driver not loaded, or card not enumerated")


@pytest.fixture
def axil(require_card):
    from alivu13p import AxiLite
    with AxiLite() as a:
        yield a


@pytest.fixture
def dma(require_card):
    from alivu13p import Dma
    with Dma() as d:
        yield d
