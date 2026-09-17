# Two QSFP28 cages.
#
# Numbering: cage 0 is the one nearer the PCIe fingers, cage 1 is the one further away.
# Positional rather than silkscreen-based, because it is the property you can check by
# looking at the card.
#
#   cage   bank   channels              reference clock
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

# Module control, bank 68.
set_property PACKAGE_PIN BF12 [get_ports qsfp0_i2c_scl]
set_property PACKAGE_PIN BD9  [get_ports qsfp0_i2c_sda]
set_property PACKAGE_PIN BB11 [get_ports qsfp0_modprsl]
set_property PACKAGE_PIN BC11 [get_ports qsfp0_intl]
set_property PACKAGE_PIN BB10 [get_ports qsfp0_resetl]
set_property PACKAGE_PIN BB7  [get_ports qsfp0_lpmode]

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

# Module control, bank 68.
set_property PACKAGE_PIN BD8  [get_ports qsfp1_i2c_scl]
set_property PACKAGE_PIN BC12 [get_ports qsfp1_i2c_sda]
set_property PACKAGE_PIN BC7  [get_ports qsfp1_modprsl]
set_property PACKAGE_PIN BC8  [get_ports qsfp1_intl]
set_property PACKAGE_PIN BA7  [get_ports qsfp1_resetl]
set_property PACKAGE_PIN BB9  [get_ports qsfp1_lpmode]

# ================================================================== module control I/O
# Bank 68 is 1.2 V. PULLUP on the open-drain and active-low lines so the board sits in a
# sane state during configuration, before the fabric drives anything.
set_property IOSTANDARD LVCMOS12 [get_ports {qsfp0_i2c_scl qsfp0_i2c_sda qsfp0_modprsl qsfp0_intl qsfp0_resetl qsfp0_lpmode}]
set_property IOSTANDARD LVCMOS12 [get_ports {qsfp1_i2c_scl qsfp1_i2c_sda qsfp1_modprsl qsfp1_intl qsfp1_resetl qsfp1_lpmode}]
set_property PULLUP true [get_ports {qsfp0_i2c_scl qsfp0_i2c_sda qsfp0_resetl}]
set_property PULLUP true [get_ports {qsfp1_i2c_scl qsfp1_i2c_sda qsfp1_resetl}]
set_property SLEW SLOW [get_ports {qsfp0_i2c_scl qsfp0_i2c_sda qsfp1_i2c_scl qsfp1_i2c_sda}]

# Sideband is software-paced and asynchronous to every clock in the design.
set_false_path -to   [get_ports {qsfp0_i2c_* qsfp0_resetl qsfp0_lpmode qsfp1_i2c_* qsfp1_resetl qsfp1_lpmode}]
set_false_path -from [get_ports {qsfp0_i2c_* qsfp0_modprsl qsfp0_intl qsfp1_i2c_* qsfp1_modprsl qsfp1_intl}]

# ======================================================================== cage LEDs
# Two per cage, bank 64. What they mean is entirely up to the design driving them --
# they are not wired to any link status in hardware.
set_property PACKAGE_PIN BD21 [get_ports {qsfp_led_y[0]}]
set_property PACKAGE_PIN BE21 [get_ports {qsfp_led_y[1]}]
set_property PACKAGE_PIN BE22 [get_ports {qsfp_led_g[0]}]
set_property PACKAGE_PIN BF22 [get_ports {qsfp_led_g[1]}]
set_property IOSTANDARD LVCMOS12 [get_ports {qsfp_led_y[*] qsfp_led_g[*]}]
set_false_path -to [get_ports {qsfp_led_y[*] qsfp_led_g[*]}]

# ========================================================================= the trap
# ResetL is active low, and an undeclared pin falls to BITSTREAM.CONFIG.UNUSEDPIN, which
# defaults to Pulldown. A design that does not declare these ports therefore holds both
# modules in permanent reset.
#
# It survives testing because passive copper DACs have no module logic to reset and link
# anyway. Optical, AOC and retimed modules never come up. Drive resetl high and lpmode
# low as real ports in any design that will see a module with electronics in it.
