# Build the reference-clock probe.
#
#   vivado -mode batch -source tcl/prj.tcl -tclargs <outdir> [jobs]
#
# Generates the VIO used for readout, builds, and writes both the bitstream and the .ltx.
# The .ltx is not optional: without it Hardware Manager cannot resolve the VIO and the
# device looks like it has no debug cores at all.

set here [file normalize [file dirname [info script]]/..]
set outdir [lindex $argv 0]
set jobs   [expr {[llength $argv] > 1 ? [lindex $argv 1] : 8}]
if {$outdir eq ""} { puts "usage: -tclargs <outdir> \[jobs\]"; exit 2 }

set part     xcvu13p-fhgb2104-2L-e
set top      clk_probe_top
set prj_name clk_probe

file mkdir $outdir
create_project -force $prj_name $outdir/$prj_name -part $part

add_files -fileset sources_1 [glob $here/rtl/*.v]
add_files -fileset constrs_1 [glob $here/xdc/*.xdc]
set_property top $top [current_fileset]

# ------------------------------------------------------------------------ readout IP
# Twelve 32-bit counts plus two 12-bit summary vectors. Input probes only -- nothing here
# needs to be driven from the host.
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_probe
set probe_cfg [list \
    CONFIG.C_NUM_PROBE_IN   {14} \
    CONFIG.C_NUM_PROBE_OUT  {0}  \
    CONFIG.C_EN_PROBE_IN_ACTIVITY {1} \
]
for {set i 0} {$i < 12} {incr i} {
    lappend probe_cfg CONFIG.C_PROBE_IN${i}_WIDTH {32}
}
lappend probe_cfg CONFIG.C_PROBE_IN12_WIDTH {12}
lappend probe_cfg CONFIG.C_PROBE_IN13_WIDTH {12}
set_property -dict $probe_cfg [get_ips vio_probe]
generate_target all [get_ips vio_probe]

# ------------------------------------------------------------------------ build
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTHESIS FAILED"
    exit 1
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "IMPLEMENTATION FAILED"
    exit 1
}

open_run impl_1
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "TIMING: WNS=$wns WHS=$whs"

# Probes file, so the VIO is visible in Hardware Manager.
write_debug_probes -force $outdir/${prj_name}.ltx
file copy -force [get_property DIRECTORY [get_runs impl_1]]/${top}.bit $outdir/${prj_name}.bit

puts "CLK PROBE BUILD OK"
puts "  bitstream: $outdir/${prj_name}.bit"
puts "  probes:    $outdir/${prj_name}.ltx"
