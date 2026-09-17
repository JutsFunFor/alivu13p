# PCIe edge connector: x16 Gen3 endpoint.
#
# Only three pins need constraining. The lane pins do not, and the reason is worth
# stating because the temptation to list them is strong: the PCIE40E4 hard block is
# hard-wired to a fixed set of transceiver channels, so choosing the block location and
# the link width determines the lane placement completely. Constraining the lanes as
# well creates a second source of truth that has to agree with the first, and when it
# disagrees the tool obeys the constraints and the link fails. The expected mapping is
# recorded at the bottom of this file so an implemented design can be checked against
# it, but it is deliberately not applied.
#
# The endpoint must sit at PCIE40E4_X0Y1 -- that is the block whose quads reach the edge
# connector on this board. The part has four, one per SLR.

# ---------------------------------------------------------------- reference clock
# 100 MHz, MGTREFCLK1 of bank 226. Measured at 100.0016 MHz by designs/00_clk_probe;
# the same oscillator also appears on AV11/AV10 (bank 224 MGTREFCLK1), fanned out so
# that a x16 link has a reference in reach of every quad it spans.
#
# MGTREFCLK0 of banks 224, 225 and 226 carry nothing at all. A design that selects one
# will build, meet timing, and never link.
set_property PACKAGE_PIN AK11 [get_ports pcie_refclk_p]
set_property PACKAGE_PIN AK10 [get_ports pcie_refclk_n]
create_clock -period 10.000 -name pcie_refclk [get_ports pcie_refclk_p]

# ------------------------------------------------------------------------- PERST
# AR26 is the device's dedicated PERSTN0 pin for bank 65 -- the silicon names it that,
# so this is the intended reset input rather than a guess among general-purpose pins.
#
# The I/O standard is the one unverified claim on this page: bank 65's VCCO cannot be
# read out of the part, and PERST is the only signal this repository places in that
# bank, so there is no second port to cross-check against. It is asserted to be 1.2 V by
# analogy with bank 64 next door. If that is wrong the endpoint never leaves reset and
# never enumerates, which makes host enumeration itself the test of this line.
set_property PACKAGE_PIN AR26 [get_ports pcie_perst_n]
set_property IOSTANDARD LVCMOS12 [get_ports pcie_perst_n]

# Reset is asynchronous to everything, and long besides.
set_false_path -from [get_ports pcie_perst_n]

# ----------------------------------------------------------------------- link LED
# A green LED at the bracket, bank 64. The cheapest possible link indicator: it needs no
# host software, no driver and no enumeration, so it distinguishes "the link never
# trained" from "the link trained but Linux cannot see the device" -- which are the two
# failures that look identical from the host.
set_property PACKAGE_PIN BD20 [get_ports pcie_link_up]
set_property IOSTANDARD LVCMOS12 [get_ports pcie_link_up]
set_false_path -to [get_ports pcie_link_up]

# ------------------------------------------------- expected lane placement (reference)
# Not constraints. This is what PCIE40E4_X0Y1 at x16 produces on its own, confirmed
# against the device package database by xdc/tools/validate_pins.py: every lane's RX and
# TX pins resolve to the same GTYE4_CHANNEL, and the sixteen channels run X1Y31 down to
# X1Y16 without a gap. Check an implemented design against this table; do not apply it.
#
#   lane   RX p/n     TX p/n     quad   channel
#    0     AF2 AF1    AF7 AF6     227   GTYE4_CHANNEL_X1Y31
#    1     AG4 AG3    AG9 AG8     227   GTYE4_CHANNEL_X1Y30
#    2     AH2 AH1    AH7 AH6     227   GTYE4_CHANNEL_X1Y29
#    3     AJ4 AJ3    AJ9 AJ8     227   GTYE4_CHANNEL_X1Y28
#    4     AK2 AK1    AK7 AK6     226   GTYE4_CHANNEL_X1Y27
#    5     AL4 AL3    AL9 AL8     226   GTYE4_CHANNEL_X1Y26
#    6     AM2 AM1    AM7 AM6     226   GTYE4_CHANNEL_X1Y25
#    7     AN4 AN3    AN9 AN8     226   GTYE4_CHANNEL_X1Y24
#    8     AP2 AP1    AP7 AP6     225   GTYE4_CHANNEL_X1Y23
#    9     AR4 AR3    AR9 AR8     225   GTYE4_CHANNEL_X1Y22
#   10     AT2 AT1    AT7 AT6     225   GTYE4_CHANNEL_X1Y21
#   11     AU4 AU3    AU9 AU8     225   GTYE4_CHANNEL_X1Y20
#   12     AV2 AV1    AV7 AV6     224   GTYE4_CHANNEL_X1Y19
#   13     AW4 AW3    BB5 BB4     224   GTYE4_CHANNEL_X1Y18
#   14     BA2 BA1    BD5 BD4     224   GTYE4_CHANNEL_X1Y17
#   15     BC2 BC1    BF5 BF4     224   GTYE4_CHANNEL_X1Y16
#
# Narrower links use the quads nearest lane 0: x1 and x4 stay inside 227, x8 adds 226,
# x16 adds 225 and 224.
