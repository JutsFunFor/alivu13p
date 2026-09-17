# Bitstream and configuration settings shared by every design here.
#
# These are not pin assignments -- they control how the device configures itself and what
# happens to pins nobody claimed.

# QSPI flash: four-bit bus, 32-bit addressing (the flash is larger than 128 Mb, so three
# address bytes cannot reach all of it).
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 51.0 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Configuration bank voltage.
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]

# Unclaimed pins are pulled down. This is the safe default for this board, with one
# consequence that has to be remembered rather than discovered: a QSFP module's ResetL
# is active low, so a design that leaves it unclaimed holds the module in reset. See the
# note at the end of qsfp_sideband.xdc.
set_property BITSTREAM.CONFIG.UNUSEDPIN Pulldown [current_design]
