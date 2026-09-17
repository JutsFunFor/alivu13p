# QSFP28 transceivers: reference clocks and the 8 lanes of both cages.
#
# Numbering: cage 0 is the one nearer the PCIe fingers, cage 1 is the one further away.
# Positional rather than silkscreen-based, because it is the property you can check by
# looking at the card.
#
#   cage   bank   channels                 reference clock
#     0    229    GTYE4_CHANNEL_X1Y36-39   Y11 / Y10   MGTREFCLK0_229
#     1    233    GTYE4_CHANNEL_X1Y52-55   D11 / D10   MGTREFCLK0_233
#
# Both reference clocks measured at 161.13 MHz. MGTREFCLK1 of both banks -- V11/V10 and
# B11/B10 -- has no oscillator behind it and reads as noise; do not select it.
#
# 161.1328125 MHz is the standard Ethernet transceiver reference: x160 gives 25.78125
# Gbps per lane, x80 gives 12.890625 Gbps.
#
# Lane order runs straight through here, lane n on channel n, unlike the PCIe hard block
# whose lane 0 sits at the top of its range.
#
# The module sideband -- I2C, ModPrsL, IntL, ResetL, LPMode and the cage LEDs -- is a
# separate interface in ordinary fabric I/O, and lives in qsfp_sideband.xdc. A design
# that talks to the modules but not through the transceivers needs only that file. A
# design that drives the lanes needs both: leaving the sideband undeclared holds the
# modules in reset, which is the trap described at the end of that file.

# ============================================================== cage 0 (near fingers)
set_property PACKAGE_PIN Y11  [get_ports qsfp0_refclk_p]
set_property PACKAGE_PIN Y10  [get_ports qsfp0_refclk_n]
create_clock -period 6.206 -name qsfp0_refclk [get_ports qsfp0_refclk_p]

set_property PACKAGE_PIN AA4  [get_ports {qsfp0_rx_p[0]}]
set_property PACKAGE_PIN AA3  [get_ports {qsfp0_rx_n[0]}]
set_property PACKAGE_PIN Y2   [get_ports {qsfp0_rx_p[1]}]
set_property PACKAGE_PIN Y1   [get_ports {qsfp0_rx_n[1]}]
set_property PACKAGE_PIN W4   [get_ports {qsfp0_rx_p[2]}]
set_property PACKAGE_PIN W3   [get_ports {qsfp0_rx_n[2]}]
set_property PACKAGE_PIN V2   [get_ports {qsfp0_rx_p[3]}]
set_property PACKAGE_PIN V1   [get_ports {qsfp0_rx_n[3]}]
set_property PACKAGE_PIN AA9  [get_ports {qsfp0_tx_p[0]}]
set_property PACKAGE_PIN AA8  [get_ports {qsfp0_tx_n[0]}]
set_property PACKAGE_PIN Y7   [get_ports {qsfp0_tx_p[1]}]
set_property PACKAGE_PIN Y6   [get_ports {qsfp0_tx_n[1]}]
set_property PACKAGE_PIN W9   [get_ports {qsfp0_tx_p[2]}]
set_property PACKAGE_PIN W8   [get_ports {qsfp0_tx_n[2]}]
set_property PACKAGE_PIN V7   [get_ports {qsfp0_tx_p[3]}]
set_property PACKAGE_PIN V6   [get_ports {qsfp0_tx_n[3]}]

# ============================================================== cage 1 (far from fingers)
set_property PACKAGE_PIN D11  [get_ports qsfp1_refclk_p]
set_property PACKAGE_PIN D10  [get_ports qsfp1_refclk_n]
create_clock -period 6.206 -name qsfp1_refclk [get_ports qsfp1_refclk_p]

set_property PACKAGE_PIN E4   [get_ports {qsfp1_rx_p[0]}]
set_property PACKAGE_PIN E3   [get_ports {qsfp1_rx_n[0]}]
set_property PACKAGE_PIN D2   [get_ports {qsfp1_rx_p[1]}]
set_property PACKAGE_PIN D1   [get_ports {qsfp1_rx_n[1]}]
set_property PACKAGE_PIN C4   [get_ports {qsfp1_rx_p[2]}]
set_property PACKAGE_PIN C3   [get_ports {qsfp1_rx_n[2]}]
set_property PACKAGE_PIN A5   [get_ports {qsfp1_rx_p[3]}]
set_property PACKAGE_PIN A4   [get_ports {qsfp1_rx_n[3]}]
set_property PACKAGE_PIN E9   [get_ports {qsfp1_tx_p[0]}]
set_property PACKAGE_PIN E8   [get_ports {qsfp1_tx_n[0]}]
set_property PACKAGE_PIN D7   [get_ports {qsfp1_tx_p[1]}]
set_property PACKAGE_PIN D6   [get_ports {qsfp1_tx_n[1]}]
set_property PACKAGE_PIN C9   [get_ports {qsfp1_tx_p[2]}]
set_property PACKAGE_PIN C8   [get_ports {qsfp1_tx_n[2]}]
set_property PACKAGE_PIN A9   [get_ports {qsfp1_tx_p[3]}]
set_property PACKAGE_PIN A8   [get_ports {qsfp1_tx_n[3]}]
