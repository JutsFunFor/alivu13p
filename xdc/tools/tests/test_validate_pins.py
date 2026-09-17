"""Prove each check in validate_pins.py actually fires.

A validator that has only ever passed is not evidence of anything -- it might be
matching nothing at all. Each case here is a constraint file with one deliberate defect,
and the test asserts the checker rejects it. The last case asserts it accepts a correct
file, so the suite cannot be satisfied by a checker that simply fails everything.

    python3 -m pytest xdc/tools/tests/ -v
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[1]
VALIDATE = TOOLS / "validate_pins.py"


def run(tmp_path: Path, text: str) -> subprocess.CompletedProcess:
    xdc = tmp_path / "case.xdc"
    xdc.write_text(text)
    return subprocess.run(
        [sys.executable, str(VALIDATE), str(xdc)],
        capture_output=True, text=True,
    )


def test_accepts_a_correct_file(tmp_path):
    """The control. Without it, a checker that rejects everything would pass the rest."""
    r = run(tmp_path, """
set_property PACKAGE_PIN AY23 [get_ports sysclk_p]
set_property PACKAGE_PIN BA23 [get_ports sysclk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sysclk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sysclk_n]
set_property PACKAGE_PIN BA20 [get_ports {user_led[0]}]
set_property IOSTANDARD LVCMOS12 [get_ports {user_led[*]}]
""")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "all checks passed" in r.stdout


@pytest.mark.parametrize("standard", [
    "SSTL12_DCI", "POD12_DCI", "DIFF_POD12", "DIFF_POD12_DCI",
    "DIFF_SSTL12_DCI",
])
def test_ddr4_standards_share_1v2_bank(tmp_path, standard):
    r = run(tmp_path, f"""
set_property -dict {{LOC AY23 IOSTANDARD {standard}}} [get_ports memory_signal]
set_property -dict {{LOC BA20 IOSTANDARD LVCMOS12}} [get_ports led]
""")
    assert r.returncode == 0, r.stdout + r.stderr


def test_rejects_a_pin_that_does_not_exist(tmp_path):
    r = run(tmp_path, "set_property PACKAGE_PIN ZZ999 [get_ports nonsense]\n")
    assert r.returncode == 1
    assert "no such package pin" in r.stdout


def test_rejects_two_ports_on_one_pin(tmp_path):
    """The defect that motivated the tool: a board file assigning main I2C and a QSFP
    cage's I2C to the same pins. Invisible until both are used at once."""
    r = run(tmp_path, """
set_property -dict {LOC BD8 IOSTANDARD LVCMOS12} [get_ports main_iic_sda]
set_property -dict {LOC BD8 IOSTANDARD LVCMOS12} [get_ports qsfp1_i2c_scl]
""")
    assert r.returncode == 1
    assert "claimed by 2 different ports" in r.stdout


def test_rejects_one_bank_needing_two_voltages(tmp_path):
    """Bank 64 has a single VCCO, so 1.2 V and 1.8 V signalling cannot both be right."""
    r = run(tmp_path, """
set_property -dict {LOC BA20 IOSTANDARD LVCMOS12} [get_ports {user_led[0]}]
set_property -dict {LOC BB20 IOSTANDARD LVCMOS18} [get_ports {user_led[1]}]
""")
    assert r.returncode == 1
    assert "more than one VCCO" in r.stdout


def test_rejects_a_mispaired_differential_half(tmp_path):
    """BA23 is the N half of AY23's pair; BA22 belongs to a different pair entirely."""
    r = run(tmp_path, """
set_property PACKAGE_PIN AY23 [get_ports sysclk_p]
set_property PACKAGE_PIN BA22 [get_ports sysclk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sysclk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sysclk_n]
""")
    assert r.returncode == 1
    assert "not the two halves of one package pair" in r.stdout


def test_rejects_a_lane_split_across_channels(tmp_path):
    """AF2/AF7 are RX and TX of one channel; AG9 is the next channel's TX."""
    r = run(tmp_path, """
set_property PACKAGE_PIN AF2 [get_ports {pcie_rx_p[0]}]
set_property PACKAGE_PIN AG9 [get_ports {pcie_tx_p[0]}]
""")
    assert r.returncode == 1
    assert "on different channels" in r.stdout


def test_rejects_an_unknown_io_standard(tmp_path):
    """Rather than skipping it, which would let an unchecked bank through silently."""
    r = run(tmp_path, "set_property -dict {LOC BA20 IOSTANDARD LVCMOS33} [get_ports x]\n")
    assert r.returncode == 1
    assert "not in this script's VCCO table" in r.stdout


def test_ignores_commented_constraints(tmp_path):
    """This repository comments out constraints that are correct but inapplicable, and a
    validator that read them would report conflicts no build can ever have."""
    r = run(tmp_path, """
set_property PACKAGE_PIN BD8 [get_ports qsfp1_i2c_scl]
# set_property PACKAGE_PIN BD8 [get_ports main_iic_sda]
set_property IOSTANDARD LVCMOS12 [get_ports qsfp1_i2c_scl]
""")
    assert r.returncode == 0, r.stdout + r.stderr


@pytest.mark.parametrize("path", sorted((TOOLS.parent).glob("*.xdc")))
def test_repository_constraints_pass(path):
    """Every committed constraint file, checked individually as well as together."""
    r = subprocess.run([sys.executable, str(VALIDATE), str(path)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


# ---------------------------------------------------------------- generated files
# The DDR4 constraints are produced by gen_ddr4_xdc.py from a reference project that is
# not redistributable, so CI cannot regenerate them and diff. What it can do is check the
# properties a hand-edit would break: the count is fixed by the interface, and the header
# is what tells the next person not to edit the file in the first place.

DDR4_FILES = sorted((TOOLS.parent).glob("ddr4_c?.xdc"))
PINS_PER_CHANNEL = 117


def test_all_four_ddr4_channels_are_present():
    assert [p.name for p in DDR4_FILES] == [f"ddr4_c{n}.xdc" for n in range(4)]


@pytest.mark.parametrize("path", DDR4_FILES, ids=lambda p: p.name)
def test_ddr4_file_is_complete(path):
    lines = [l for l in path.read_text().splitlines()
             if l.startswith("set_property PACKAGE_PIN")]
    assert len(lines) == PINS_PER_CHANNEL, (
        f"{path.name} has {len(lines)} pins, expected {PINS_PER_CHANNEL}. "
        f"Regenerate it rather than editing: xdc/tools/gen_ddr4_xdc.py"
    )


@pytest.mark.parametrize("path", DDR4_FILES, ids=lambda p: p.name)
def test_ddr4_file_says_it_is_generated(path):
    head = path.read_text()[:800]
    assert "gen_ddr4_xdc.py" in head and "do not hand-edit" in head
