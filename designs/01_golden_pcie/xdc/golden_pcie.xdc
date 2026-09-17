# Design-specific constraints for the PCIe bring-up design.
#
# Board pinout comes from xdc/ at the top of the repository -- pcie.xdc, led.xdc,
# bitstream.xdc -- which the build script adds directly. Only what is specific to this
# design belongs here.

# The LEDs and the link indicator are driven from the 250 MHz AXI clock, and nothing
# outside the card is timed against them.
set_false_path -to [get_ports {user_led[*]}]
set_false_path -to [get_ports pcie_link_up]

# NOTE ON UNUSED PINS
#
# bitstream.xdc sets UNUSEDPIN to Pulldown, and this design does not declare the QSFP
# module-control pins. Both cages therefore sit with ResetL low, which is asserted, for
# as long as this bitstream is loaded. That is harmless here -- this design does not
# touch the transceivers at all -- but it matters if this image is ever flashed as the
# power-on golden image, because then a module would be held in reset until something
# else was loaded. Add the module-control ports before promoting it.
