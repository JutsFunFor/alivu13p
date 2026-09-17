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

# The configuration watchdog. This is what makes fallback actually happen: if
# configuration stalls or the image is corrupt, the timer expires and the device falls
# back instead of sitting there half-configured.
#
# It lives here rather than in bitstream.xdc, and that placement is not cosmetic. The
# timer is armed whenever it is set, not only when fallback is enabled, and it runs
# during configuration. At ~0.67 s it expires long before a 36 MB bitstream finishes
# loading over JTAG, which aborts the load: the device reports a watchdog timeout and a
# bad packet error, the startup state machine never leaves phase 0, and DONE stays low.
# The symptom looks like a corrupt bitstream rather than a bitstream setting.
#
# Flash configuration is fast enough that this does not arise, which is exactly the case
# this file is for.
set_property BITSTREAM.CONFIG.TIMER_CFG 0x01FFFFFF [current_design]
