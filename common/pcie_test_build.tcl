# Shared build flow for the two PCIe data-path examples.
set repo [file normalize $here/../..]
set outdir [file normalize [lindex $argv 0]]
set jobs [expr {[llength $argv] > 1 ? [lindex $argv 1] : 8}]
set part xcvu13p-fhgb2104-2L-e
set top ${prj_name}_top
file mkdir $outdir
create_project -force $prj_name $outdir/$prj_name -part $part
set_param general.maxThreads $jobs
add_files [glob $here/rtl/*.v]
add_files -fileset constrs_1 [list $repo/xdc/pcie.xdc $repo/xdc/led.xdc $repo/xdc/bitstream.xdc $here/xdc/timing.xdc]
# The design's own timing exceptions are read last. They refer to clocks that IP creates
# -- the memory controller's input clock, for one -- and a get_clocks that runs before
# the clock exists returns nothing, which makes the constraint vanish with a warning
# rather than an error.
set_property PROCESSING_ORDER LATE [get_files $here/xdc/timing.xdc]
set_property top $top [current_fileset]
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

if {$mode eq "stream"} {
    set_property CONFIG.xdma_axi_intf_mm AXI_Stream [get_ips xdma_0]
}
create_ip -name axi_crossbar -vendor xilinx.com -library ip -module_name axi_xbar_lite
set_property -dict [list \
    CONFIG.NUM_SI {1} CONFIG.NUM_MI {2} \
    CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {32} CONFIG.DATA_WIDTH {32} \
    CONFIG.M00_A00_BASE_ADDR {0x0000000000030000} CONFIG.M00_A00_ADDR_WIDTH {16} \
    CONFIG.M01_A00_BASE_ADDR {0x0000000000040000} CONFIG.M01_A00_ADDR_WIDTH {16} \
] [get_ips axi_xbar_lite]

create_ip -name axi_gpio -vendor xilinx.com -library ip -module_name axi_gpio_led
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH  {8} CONFIG.C_ALL_OUTPUTS   {1} \
    CONFIG.C_IS_DUAL     {1} \
    CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_INPUTS_2 {1} \
] [get_ips axi_gpio_led]

# -------------------------------------------------------------- XVC over PCIe
# C_DEBUG_MODE 2 is the AXI-to-JTAG bridge: the host opens /dev/xdma0_user, xvc_pcie
# serves it as a virtual cable, and Hardware Manager connects with no cable attached.
create_ip -name debug_bridge -vendor xilinx.com -library ip -module_name debug_bridge_xvc
set_property -dict [list CONFIG.C_DEBUG_MODE {2}] [get_ips debug_bridge_xvc]

if {$mode eq "ddr4"} {
    add_files -fileset constrs_1 $repo/xdc/ddr4_c1.xdc
    create_ip -name axi_crossbar -vendor xilinx.com -library ip -module_name axi_xbar_mm
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1} \
        CONFIG.PROTOCOL {AXI4} CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} \
        CONFIG.ID_WIDTH {4} CONFIG.M00_A00_BASE_ADDR {0x0000000000000000} \
        CONFIG.M00_A00_ADDR_WIDTH {32}] [get_ips axi_xbar_mm]
    create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name axi_clock_converter_0
    set_property -dict [list CONFIG.PROTOCOL {AXI4} CONFIG.ADDR_WIDTH {64} \
        CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {4} CONFIG.ACLK_ASYNC {1}] [get_ips axi_clock_converter_0]
create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_0
set_property -dict [list \
    CONFIG.C0.DDR4_MemoryPart           {MT40A512M16HA-083E} \
    CONFIG.C0.DDR4_MemoryType           {Components} \
    CONFIG.C0.DDR4_MemoryVoltage        {1.2V} \
    CONFIG.C0.DDR4_DataWidth            {72} \
    CONFIG.C0.DDR4_Ecc                  {true} \
    CONFIG.C0.DDR4_DataMask             {NO_DM_NO_DBI} \
    CONFIG.C0.DDR4_CasLatency           {16} \
    CONFIG.C0.DDR4_CasWriteLatency      {12} \
    CONFIG.C0.DDR4_InputClockPeriod     {2499} \
    CONFIG.C0.DDR4_TimePeriod           {833} \
    CONFIG.C0.DDR4_PhyClockRatio        {4:1} \
    CONFIG.C0.DDR4_AxiSelection         {true} \
    CONFIG.C0.DDR4_AxiDataWidth         {512} \
    CONFIG.C0.DDR4_AxiAddressWidth      {32} \
    CONFIG.C0.DDR4_AxiIDWidth           {4} \
    CONFIG.C0.DDR4_AxiArbitrationScheme {RD_PRI_REG} \
    CONFIG.C0.DDR4_Mem_Add_Map          {ROW_COLUMN_BANK} \
    CONFIG.C0.DDR4_BurstLength          {8} \
    CONFIG.C0.DDR4_Ordering             {Normal} \
    CONFIG.C0.DDR4_Slot                 {Single} \
    CONFIG.C0.DDR4_Clamshell            {false} \
    CONFIG.C0.StackHeight               {1} \
    CONFIG.System_Clock                 {Differential} \
    CONFIG.Debug_Signal                 {Disable} \
] [get_ips ddr4_0]
} else {
    create_ip -name axis_data_fifo -vendor xilinx.com -library ip -module_name axis_data_fifo_0
    set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} \
        CONFIG.HAS_TLAST {1} CONFIG.FIFO_DEPTH {1024} CONFIG.FIFO_MODE {1}] [get_ips axis_data_fifo_0]
}
# MIG retains its supported OOC flow. Timing-sensitive PCIe fabric is in-context.
foreach name {xdma_0 axi_xbar_mm axi_xbar_lite axi_clock_converter_0 axis_data_fifo_0 axi_gpio_led debug_bridge_xvc} {
    set ip [get_ips -quiet $name]
    if {$ip eq ""} { continue }
    set f [get_files [get_property IP_FILE $ip]]
    set_property generate_synth_checkpoint false $f
}
foreach ip [get_ips] { generate_target all $ip }
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
source $repo/common/pcie_test_finish.tcl
