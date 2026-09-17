# LEDs and the link indicator are not a timed interface.
set_false_path -to [get_ports {user_led[*] pcie_link_up}]

# The SPI controller's reference clock is the board oscillator; its AXI side runs on the
# PCIe user clock. They share no source, and the IP crosses between them internally with
# Async_Clk set. One group named here means "asynchronous to every other clock in the
# design", which is the honest statement and does not need to name the PCIe clock -- a
# name the endpoint IP chooses, not this design.
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks sysclk]

# The module sideband synchronizers. The first stage is asynchronous by construction.
set_false_path -to [get_pins -hier -regexp {.*(prs0_sync|int0_sync|prs1_sync|int1_sync)_reg\[0\]/D}]
