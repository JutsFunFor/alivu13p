# Golden image settings -- add to a design only if it is the one flashed at address 0.
#
# The golden image is what the device loads at power-on. Its job is to be boringly
# reliable: if the multiboot image at the next address fails to load, the configuration
# engine falls back here, so the card always comes up as a working PCIe endpoint even
# after a bad update.
#
# Applying these to a design flashed anywhere other than address 0 makes the fallback
# point at the wrong place, which is worse than not having one.

set_property BITSTREAM.CONFIG.CONFIGFALLBACK ENABLE [current_design]
set_property BITSTREAM.CONFIG.NEXT_CONFIG_ADDR 0x04000000 [current_design]
