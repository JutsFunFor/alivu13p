# Enumerate every JTAG target and the devices on it.
#
#   vivado -nojournal -nolog -mode batch -source tools/jtag_scan.tcl
#
# Run this before programming anything. Vivado's convention of taking
# [lindex [get_hw_targets] 0] is only safe when exactly one cable is attached, and a
# workstation used for FPGA work rarely has exactly one. Programming the wrong device
# is silent -- it succeeds, on the wrong board.
#
# Use the printed target string explicitly in any programming script.

open_hw_manager
connect_hw_server -quiet

set targets [get_hw_targets -quiet]
if {[llength $targets] == 0} {
    puts "NO JTAG TARGETS. Check the cable, and that the cable drivers are installed."
    exit 1
}

puts "\n=== JTAG targets ==="
foreach t $targets {
    puts "TARGET $t"
    if {[catch {open_hw_target $t} err]} {
        # A target can refuse to open because another process holds it, or because it
        # has no board powered on the other end. Neither is fatal to the scan.
        puts "   unavailable: [string trim [lindex [split $err \n] 0]]"
        continue
    }
    foreach d [get_hw_devices -quiet] {
        set part [get_property -quiet PART $d]
        set done [get_property -quiet REGISTER.IR.BIT5_DONE $d]
        puts [format "   DEVICE %-14s part=%-12s DONE=%s" $d $part $done]
    }
    close_hw_target
}
puts ""
