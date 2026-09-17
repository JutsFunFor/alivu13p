# designs/06_board_mgmt -- configuration flash and QSFP module I2C, reached over PCIe.
#
# IP versions are resolved from whatever catalog is installed rather than pinned, so this
# survives a Vivado upgrade. Every IP here exists in 2025.2; none of them is a block
# design, so there is no version gate to soften and no .bd to migrate.
set here [file normalize [file dirname [info script]]/..]
set repo [file normalize $here/../..]
if {[llength $argv] < 1} { puts "usage: -tclargs <outdir> \[jobs\]"; exit 2 }
set outdir [file normalize [lindex $argv 0]]
set jobs [expr {[llength $argv] > 1 ? [lindex $argv 1] : 8}]
set part xcvu13p-fhgb2104-2L-e
set prj_name board_mgmt
set top ${prj_name}_top

if {[catch {

file mkdir $outdir
create_project -force $prj_name $outdir/$prj_name -part $part
set_param general.maxThreads $jobs
add_files [glob $here/rtl/*.v]
set_property top $top [current_fileset]

# qsfp_gty.xdc is deliberately absent: this design has no transceivers. qsfp_sideband.xdc
# is the half that matters here, and it is used whole -- every port it names is declared.
add_files -fileset constrs_1 [list \
    $repo/xdc/pcie.xdc \
    $repo/xdc/clocks.xdc \
    $repo/xdc/led.xdc \
    $repo/xdc/qsfp_sideband.xdc \
    $repo/xdc/bitstream.xdc \
    $here/xdc/timing.xdc \
]

# The timing exceptions are for implementation only. Vivado 2025.2 segfaults inside its
# synthesis timing engine on this design when they are applied during synthesis -- a
# tool crash, reproducibly at "Start Timing Optimization", with the stack in
# worstSlackEndPoint. They buy nothing there in any case: synthesis has no placement, so
# relaxing a path it was never going to fail changes no decision it makes. Signoff
# happens against the implemented design, which still sees every one of them.
set_property used_in_synthesis false [get_files $here/xdc/timing.xdc]

# ------------------------------------------------------------------- PCIe endpoint
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_0
set_property -dict [list \
    CONFIG.mode_selection             {Advanced} \
    CONFIG.pcie_blk_locn              {X0Y1} \
    CONFIG.pl_link_cap_max_link_width {X16} \
    CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
    CONFIG.axisten_freq               {250} \
    CONFIG.axi_data_width             {512_bit} \
    CONFIG.axi_addr_width             {64} \
    CONFIG.xdma_axi_intf_mm           {AXI_Memory_Mapped} \
    CONFIG.axilite_master_en          {true} \
    CONFIG.axilite_master_scale       {Kilobytes} \
    CONFIG.axilite_master_size        {512} \
    CONFIG.xdma_num_usr_irq           {1} \
    CONFIG.xdma_rnum_chnl             {1} \
    CONFIG.xdma_wnum_chnl             {1} \
    CONFIG.sys_reset_polarity         {ACTIVE_LOW} \
    CONFIG.ref_clk_freq               {100_MHz} \
] [get_ips xdma_0]

# ------------------------------------------------------------------- DMA target
# Same address, width and depth as designs/01_golden_pcie, so the host's DMA tests run
# against this bitstream without being told which design is loaded.
create_ip -name axi_crossbar -vendor xilinx.com -library ip -module_name axi_xbar_mm
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1} \
    CONFIG.PROTOCOL {AXI4} CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} \
    CONFIG.ID_WIDTH {4} CONFIG.M00_A00_BASE_ADDR {0x00000000c0000000} \
    CONFIG.M00_A00_ADDR_WIDTH {16}] [get_ips axi_xbar_mm]

# ID_WIDTH must match the crossbar. The default of zero removes the ID ports entirely,
# which leaves the crossbar's BID and RID inputs undriven -- synthesis passes with a
# warning and opt_design then fails inside the crossbar over a LUT input connected to
# nothing.
create_ip -name axi_bram_ctrl -vendor xilinx.com -library ip -module_name axi_bram_ctrl_0
set_property -dict [list \
    CONFIG.DATA_WIDTH {512} CONFIG.SUPPORTS_NARROW_BURST {0} \
    CONFIG.SINGLE_PORT_BRAM {1} CONFIG.ECC_TYPE {0} CONFIG.MEM_DEPTH {1024} \
    CONFIG.ID_WIDTH {4} \
] [get_ips axi_bram_ctrl_0]

create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name blk_mem_bram
set_property -dict [list \
    CONFIG.Interface_Type {Native} CONFIG.Memory_Type {Single_Port_RAM} \
    CONFIG.Use_Byte_Write_Enable {true} CONFIG.Byte_Size {8} \
    CONFIG.Write_Width_A {512} CONFIG.Write_Depth_A {1024} CONFIG.Read_Width_A {512} \
    CONFIG.Enable_A {Use_ENA_Pin} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.PRIM_type_to_Implement {BRAM} \
] [get_ips blk_mem_bram]

# ---------------------------------------------------------------- register crossbar
create_ip -name axi_crossbar -vendor xilinx.com -library ip -module_name axi_xbar_lite
set_property -dict [list \
    CONFIG.NUM_SI {1} CONFIG.NUM_MI {6} \
    CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {32} CONFIG.DATA_WIDTH {32} \
    CONFIG.M00_A00_BASE_ADDR {0x0000000000010000} CONFIG.M00_A00_ADDR_WIDTH {16} \
    CONFIG.M01_A00_BASE_ADDR {0x0000000000030000} CONFIG.M01_A00_ADDR_WIDTH {16} \
    CONFIG.M02_A00_BASE_ADDR {0x0000000000040000} CONFIG.M02_A00_ADDR_WIDTH {16} \
    CONFIG.M03_A00_BASE_ADDR {0x0000000000050000} CONFIG.M03_A00_ADDR_WIDTH {16} \
    CONFIG.M04_A00_BASE_ADDR {0x0000000000060000} CONFIG.M04_A00_ADDR_WIDTH {16} \
    CONFIG.M05_A00_BASE_ADDR {0x0000000000070000} CONFIG.M05_A00_ADDR_WIDTH {16} \
] [get_ips axi_xbar_lite]

# ------------------------------------------------------------- configuration flash
# C_USE_STARTUP routes the controller to the dedicated configuration pins through
# STARTUPE3, so the flash needs no pin constraints and no fabric I/O.
#
# Standard SPI, not quad: a JEDEC ID read works on every SPI flash ever made, and this
# design has no idea yet which part is fitted -- finding that out is the point.
# ext_spi_clk is the 100 MHz board oscillator and C_SCK_RATIO divides it, giving SCK at
# 6.25 MHz, comfortably inside the slowest plausible flash's rating.
create_ip -name axi_quad_spi -vendor xilinx.com -library ip -module_name axi_quad_spi_0
set_property -dict [list \
    CONFIG.C_USE_STARTUP     {1} \
    CONFIG.C_USE_STARTUP_INT {1} \
    CONFIG.C_SPI_MODE        {0} \
    CONFIG.C_NUM_SS_BITS     {1} \
    CONFIG.C_SCK_RATIO       {16} \
    CONFIG.C_FIFO_DEPTH      {16} \
    CONFIG.Async_Clk         {1} \
    CONFIG.Master_mode       {1} \
    CONFIG.C_TYPE_OF_AXI4_INTERFACE {0} \
] [get_ips axi_quad_spi_0]

# ------------------------------------------------------------------- module I2C
# AXI_ACLK_FREQ_MHZ is not documentation: the IP computes its bit-timing dividers from
# it. Getting it wrong produces a bus that runs at the wrong speed rather than an error.
create_ip -name axi_iic -vendor xilinx.com -library ip -module_name axi_iic_0
set_property -dict [list \
    CONFIG.AXI_ACLK_FREQ_MHZ {250} \
    CONFIG.IIC_FREQ_KHZ      {100} \
    CONFIG.C_SDA_LEVEL       {1} \
] [get_ips axi_iic_0]

# ---------------------------------------------------------------------- GPIO
create_ip -name axi_gpio -vendor xilinx.com -library ip -module_name axi_gpio_led
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH  {8} CONFIG.C_ALL_OUTPUTS   {1} \
    CONFIG.C_IS_DUAL     {1} \
    CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_INPUTS_2 {1} \
] [get_ips axi_gpio_led]

# C_DOUT_DEFAULT is the reset value of the output data register, and here it is the
# whole point: bits 0 and 2 are the two ResetL lines, so both modules come out of reset
# the instant the design does, with no host software involved.
create_ip -name axi_gpio -vendor xilinx.com -library ip -module_name axi_gpio_qsfp
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH  {8} CONFIG.C_ALL_OUTPUTS   {1} \
    CONFIG.C_DOUT_DEFAULT {0x00000005} \
    CONFIG.C_IS_DUAL     {1} \
    CONFIG.C_GPIO2_WIDTH {8} CONFIG.C_ALL_INPUTS_2 {1} \
] [get_ips axi_gpio_qsfp]

# ------------------------------------------------------------------ XVC over PCIe
# C_DEBUG_MODE 2 is the AXI-to-JTAG bridge: the host opens /dev/xdma0_user, xvc_pcie
# serves it as a virtual cable, and Hardware Manager connects with no cable attached.
create_ip -name debug_bridge -vendor xilinx.com -library ip -module_name debug_bridge_xvc
set_property -dict [list CONFIG.C_DEBUG_MODE {2}] [get_ips debug_bridge_xvc]

# Synthesize the IP in context rather than out of context. Out of context, each IP is
# constrained with its own default clock period -- 100 ns for a crossbar against the
# 4 ns it actually sees -- and the mismatch surfaces as timing errors that describe a
# clock nothing in this design uses.
foreach name {xdma_0 axi_xbar_mm axi_bram_ctrl_0 blk_mem_bram axi_xbar_lite
              axi_quad_spi_0 axi_iic_0 axi_gpio_led axi_gpio_qsfp debug_bridge_xvc} {
    set ip [get_ips -quiet $name]
    if {$ip eq ""} { continue }
    catch { set_property generate_synth_checkpoint false [get_files [get_property IP_FILE $ip]] }
}
foreach ip [get_ips] { generate_target all $ip }

set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]

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

} message]} {
    puts stderr "BUILD FAILED: $message"
    puts stderr $::errorInfo
    exit 1
}
exit 0
