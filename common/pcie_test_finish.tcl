# Implementation and signoff for the PCIe data-path examples.
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed" }
open_run impl_1
report_timing_summary -file $outdir/timing_summary.rpt
report_drc -file $outdir/drc.rpt
report_cdc -file $outdir/cdc.rpt
report_utilization -file $outdir/utilization.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "TIMING: WNS=$wns WHS=$whs"
if {$wns eq "" || $whs eq "" || $wns < 0 || $whs < 0} { error "Timing not closed" }
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]} { error "DRC errors" }
if {[llength [get_debug_cores -quiet]]} { write_debug_probes -force $outdir/${prj_name}.ltx }
file copy -force [get_property DIRECTORY [get_runs impl_1]]/${top}.bit $outdir/${prj_name}.bit
puts "BUILD PASS: $outdir/${prj_name}.bit"
