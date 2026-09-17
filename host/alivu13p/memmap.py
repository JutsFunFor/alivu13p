"""Address maps, expressed once.

Every design puts its peripherals somewhere, and the somewhere differs between designs.
Scattering those numbers through test code as literals is how a test ends up passing
against the wrong window -- reads from an unmapped address return zeroes or ones rather
than an error, so a wrong base address looks like broken hardware instead of a wrong
constant.

Each map here is meant to be checked against the design's build script, where the same
numbers appear as crossbar parameters.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Window:
    """One addressable region."""

    name: str
    base: int
    size: int
    kind: str  # "dma" for the memory-mapped path, "reg" for the AXI-Lite BAR

    def __contains__(self, addr: int) -> bool:
        return self.base <= addr < self.base + self.size

    def __repr__(self) -> str:
        return f"<{self.name} {self.kind} 0x{self.base:08X}+0x{self.size:X}>"


@dataclass(frozen=True)
class DesignMap:
    design: str
    windows: tuple[Window, ...]

    def __getitem__(self, name: str) -> Window:
        for w in self.windows:
            if w.name == name:
                return w
        raise KeyError(f"{self.design} has no window named {name!r}; "
                       f"it has {[w.name for w in self.windows]}")

    def of_kind(self, kind: str) -> tuple[Window, ...]:
        return tuple(w for w in self.windows if w.kind == kind)


# designs/01_golden_pcie -- mirrors the crossbar address parameters in its tcl/prj.tcl.
GOLDEN_PCIE = DesignMap(
    design="01_golden_pcie",
    windows=(
        Window("bram", 0xC000_0000, 64 * 1024, "dma"),
        Window("uram", 0xC001_0000, 64 * 1024, "dma"),
        Window("gpio", 0x0003_0000, 64 * 1024, "reg"),
        Window("xvc",  0x0004_0000, 64 * 1024, "reg"),
    ),
)

# AXI GPIO register offsets, from the IP's own documentation. Channel 1 drives the eight
# LEDs; channel 2 is the single bit wired to the endpoint's interrupt request.
GPIO_DATA1 = 0x0000
GPIO_TRI1  = 0x0004
GPIO_DATA2 = 0x0008
GPIO_TRI2  = 0x000C
