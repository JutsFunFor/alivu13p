# IBERT (GTY) loopback test for the two ALIVU13P QSFP28 cages.
#
# tclargs: <outdir> <jobs>
#
# The IBERT customization is imported from ip/ibert_ultrascale_gty_0.xci rather than
# built up with set_property calls. That is deliberate: setting the quad/refclk params
# incrementally trips an IP validation-ordering bug ("Number of Lanes ... should not
# exceed 1", and C_REFCLK_SOURCE_QUAD_* only accepts None until its quad is enabled).
# Reading the .xci validates the whole customization atomically, which works.

set outdir [lindex $argv 0]
set jobs   [lindex $argv 1]

set part    xcvu13p-fhgb2104-2L-e
set top     example_ibert_ultrascale_gty_0
set ipname  ibert_ultrascale_gty_0
set here    [file normalize [file join [file dirname [info script]] ..]]

create_project -force ibert_qsfp $outdir -part $part
set_property target_language Verilog [current_project]

# ---- IBERT IP: import + retarget to our part (xci was customized for xqvu13p-fhqb2104) ----
import_ip -name $ipname $here/ip/$ipname.xci
upgrade_ip [get_ips $ipname]
if {[get_property IS_LOCKED [get_ips $ipname]]} {
    puts "ERROR: IP $ipname is still LOCKED after upgrade_ip - cannot generate."
    exit 1
}
generate_target all [get_ips $ipname]

# ---- sources / constraints ----
add_files -fileset sources_1 $here/src/example_ibert_ultrascale_gty_0.v
add_files -fileset constrs_1 $here/xdc/example_ibert_ultrascale_gty_0.xdc
add_files -fileset constrs_1 $here/xdc/ibert_ultrascale_gty_ip_example.xdc

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

# ---- build ----
# NB: wait_on_run throws when a run fails, which would abort before the checks below
# and still leave vivado exiting 0. catch it so we always exit non-zero on failure.
launch_runs synth_1 -jobs $jobs
catch {wait_on_run synth_1}
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: synthesis failed (status: [get_property STATUS [get_runs synth_1]])"
    exit 1
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
catch {wait_on_run impl_1}
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: implementation failed (status: [get_property STATUS [get_runs impl_1]])"
    exit 1
}

open_run impl_1
report_utilization     -file $outdir/utilization.rpt
report_timing_summary  -file $outdir/timing_summary.rpt
# .ltx lets Hardware Manager associate the debug/IBERT cores with the device
write_debug_probes -force $outdir/ibert_qsfp.ltx

set bit [glob -nocomplain $outdir/ibert_qsfp.runs/impl_1/*.bit]
puts "BITSTREAM: $bit"
puts "IBERT BUILD OK"
