// Board management over PCIe: configuration flash identity and QSFP28 module I2C.
//
// Nothing here moves bulk data. The point is to reach the two board-level interfaces
// that no other design in this repository touches, and to do it from the host with no
// JTAG cable attached:
//
//   * the SPI configuration flash, through STARTUPE3 -- the same pins the FPGA booted
//     from, which is why they need no constraints;
//   * each QSFP cage's I2C bus, which is how a module says what it is (SFF-8636).
//
// The memory-mapped path carries the same 64 KiB BRAM at 0xC000_0000 as the golden
// design, at the same address and geometry, so the existing DMA tests run unchanged
// against this bitstream too.
`default_nettype none

module board_mgmt_top (
    // PCIe edge connector.
    input  wire        pcie_refclk_p,
    input  wire        pcie_refclk_n,
    input  wire        pcie_perst_n,
    input  wire [15:0] pcie_rx_p,
    input  wire [15:0] pcie_rx_n,
    output wire [15:0] pcie_tx_p,
    output wire [15:0] pcie_tx_n,

    // Green LED at the bracket, straight from the endpoint's link status.
    output wire        pcie_link_up,

    // 100 MHz board clock. Present for the SPI controller's reference, which must be
    // slow enough for the flash and so cannot be the 250 MHz PCIe user clock.
    input  wire        sysclk_p,
    input  wire        sysclk_n,

    // Eight user LEDs, host-controlled through the GPIO.
    output wire [7:0]  user_led,

    // QSFP28 module sideband. No transceivers in this design -- the lanes stay
    // undeclared on purpose, and qsfp_gty.xdc is not part of it.
    inout  wire        qsfp0_i2c_scl,
    inout  wire        qsfp0_i2c_sda,
    input  wire        qsfp0_modprsl,
    input  wire        qsfp0_intl,
    output wire        qsfp0_resetl,
    output wire        qsfp0_lpmode,
    inout  wire        qsfp1_i2c_scl,
    inout  wire        qsfp1_i2c_sda,
    input  wire        qsfp1_modprsl,
    input  wire        qsfp1_intl,
    output wire        qsfp1_resetl,
    output wire        qsfp1_lpmode,
    output wire [1:0]  qsfp_led_y,
    output wire [1:0]  qsfp_led_g
);

    // ------------------------------------------------------------ reference clock
    // The only legal route for a transceiver reference clock into the fabric.
    wire pcie_refclk_gt;
    wire pcie_refclk_div2;

    IBUFDS_GTE4 #(
        .REFCLK_HROW_CK_SEL(2'b00)
    ) u_pcie_refclk_ibuf (
        .I     (pcie_refclk_p),
        .IB    (pcie_refclk_n),
        .CEB   (1'b0),
        .O     (pcie_refclk_gt),
        .ODIV2 (pcie_refclk_div2)
    );

    // The SPI controller divides this by C_SCK_RATIO to make SCK. Taking it from the
    // board oscillator rather than from the PCIe user clock keeps SCK at a few MHz
    // without a second BUFG stage, and keeps flash access alive independently of
    // whether the link has trained.
    wire sysclk_ibuf, ext_spi_clk;
    IBUFDS u_sysclk_ibuf (.I(sysclk_p), .IB(sysclk_n), .O(sysclk_ibuf));
    BUFG   u_sysclk_bufg (.I(sysclk_ibuf), .O(ext_spi_clk));

    // ------------------------------------------------------------------ AXI fabric
    wire        axi_aclk;
    wire        axi_aresetn;

    // XDMA host-to-card memory-mapped master, 512 bits wide.
    wire [3:0]   mm_awid,   mm_arid,   mm_bid,   mm_rid;
    wire [63:0]  mm_awaddr, mm_araddr;
    wire [7:0]   mm_awlen,  mm_arlen;
    wire [2:0]   mm_awsize, mm_arsize, mm_awprot, mm_arprot;
    wire [1:0]   mm_awburst, mm_arburst, mm_bresp, mm_rresp;
    wire         mm_awlock, mm_arlock;
    wire [3:0]   mm_awcache, mm_arcache;
    wire         mm_awvalid, mm_awready, mm_arvalid, mm_arready;
    wire [511:0] mm_wdata,  mm_rdata;
    wire [63:0]  mm_wstrb;
    wire         mm_wlast,  mm_wvalid, mm_wready;
    wire         mm_bvalid, mm_bready, mm_rlast, mm_rvalid, mm_rready;

    // XDMA AXI4-Lite master, the register window behind the BAR.
    wire [31:0] axil_awaddr, axil_araddr, axil_wdata, axil_rdata;
    wire [2:0]  axil_awprot, axil_arprot;
    wire [3:0]  axil_wstrb;
    wire [1:0]  axil_bresp, axil_rresp;
    wire        axil_awvalid, axil_awready, axil_wvalid, axil_wready;
    wire        axil_bvalid, axil_bready, axil_arvalid, axil_arready;
    wire        axil_rvalid, axil_rready;

    wire        user_lnk_up;

    assign pcie_link_up = user_lnk_up;

    // Both I2C controllers and the SPI controller raise interrupts, but this design is
    // polled: every operation here completes in microseconds to milliseconds and the
    // host is already spinning on the status register. Interrupt delivery itself is
    // verified by designs/01_golden_pcie.
    wire usr_irq_req = 1'b0;

    xdma_0 u_xdma (
        .sys_clk          (pcie_refclk_div2),
        .sys_clk_gt       (pcie_refclk_gt),
        .sys_rst_n        (pcie_perst_n),
        .user_lnk_up      (user_lnk_up),

        .pci_exp_txp      (pcie_tx_p),
        .pci_exp_txn      (pcie_tx_n),
        .pci_exp_rxp      (pcie_rx_p),
        .pci_exp_rxn      (pcie_rx_n),

        .axi_aclk         (axi_aclk),
        .axi_aresetn      (axi_aresetn),

        .usr_irq_req      (usr_irq_req),
        .usr_irq_ack      (),
        .msi_enable       (),
        .msi_vector_width (),

        .m_axi_awid       (mm_awid),
        .m_axi_awaddr     (mm_awaddr),
        .m_axi_awlen      (mm_awlen),
        .m_axi_awsize     (mm_awsize),
        .m_axi_awburst    (mm_awburst),
        .m_axi_awprot     (mm_awprot),
        .m_axi_awvalid    (mm_awvalid),
        .m_axi_awready    (mm_awready),
        .m_axi_awlock     (mm_awlock),
        .m_axi_awcache    (mm_awcache),
        .m_axi_wdata      (mm_wdata),
        .m_axi_wstrb      (mm_wstrb),
        .m_axi_wlast      (mm_wlast),
        .m_axi_wvalid     (mm_wvalid),
        .m_axi_wready     (mm_wready),
        .m_axi_bid        (mm_bid),
        .m_axi_bresp      (mm_bresp),
        .m_axi_bvalid     (mm_bvalid),
        .m_axi_bready     (mm_bready),
        .m_axi_arid       (mm_arid),
        .m_axi_araddr     (mm_araddr),
        .m_axi_arlen      (mm_arlen),
        .m_axi_arsize     (mm_arsize),
        .m_axi_arburst    (mm_arburst),
        .m_axi_arprot     (mm_arprot),
        .m_axi_arvalid    (mm_arvalid),
        .m_axi_arready    (mm_arready),
        .m_axi_arlock     (mm_arlock),
        .m_axi_arcache    (mm_arcache),
        .m_axi_rid        (mm_rid),
        .m_axi_rdata      (mm_rdata),
        .m_axi_rresp      (mm_rresp),
        .m_axi_rlast      (mm_rlast),
        .m_axi_rvalid     (mm_rvalid),
        .m_axi_rready     (mm_rready),

        .m_axil_awaddr    (axil_awaddr),
        .m_axil_awprot    (axil_awprot),
        .m_axil_awvalid   (axil_awvalid),
        .m_axil_awready   (axil_awready),
        .m_axil_wdata     (axil_wdata),
        .m_axil_wstrb     (axil_wstrb),
        .m_axil_wvalid    (axil_wvalid),
        .m_axil_wready    (axil_wready),
        .m_axil_bvalid    (axil_bvalid),
        .m_axil_bresp     (axil_bresp),
        .m_axil_bready    (axil_bready),
        .m_axil_araddr    (axil_araddr),
        .m_axil_arprot    (axil_arprot),
        .m_axil_arvalid   (axil_arvalid),
        .m_axil_arready   (axil_arready),
        .m_axil_rdata     (axil_rdata),
        .m_axil_rresp     (axil_rresp),
        .m_axil_rvalid    (axil_rvalid),
        .m_axil_rready    (axil_rready),

        .cfg_mgmt_addr            (19'b0),
        .cfg_mgmt_write           (1'b0),
        .cfg_mgmt_write_data      (32'b0),
        .cfg_mgmt_byte_enable     (4'b0),
        .cfg_mgmt_read            (1'b0),
        .cfg_mgmt_read_data       (),
        .cfg_mgmt_read_write_done ()
    );

    // ------------------------------------------------------------- DMA target
    // One slave, but still behind a crossbar: the crossbar decodes, so a transfer
    // outside the 64 KiB window returns DECERR instead of silently aliasing back into
    // the memory, which is what a truncated address connection would do.
    wire [3:0]   xm_awid, xm_arid, xm_bid, xm_rid;
    wire [63:0]  xm_awaddr, xm_araddr;
    wire [7:0]   xm_awlen, xm_arlen;
    wire [2:0]   xm_awsize, xm_arsize, xm_awprot, xm_arprot;
    wire [1:0]   xm_awburst, xm_arburst, xm_bresp, xm_rresp;
    wire         xm_awlock, xm_arlock;
    wire [3:0]   xm_awcache, xm_arcache;
    wire         xm_awvalid, xm_awready, xm_arvalid, xm_arready;
    wire [511:0] xm_wdata, xm_rdata;
    wire [63:0]  xm_wstrb;
    wire         xm_wlast, xm_wvalid, xm_wready;
    wire         xm_bvalid, xm_bready, xm_rlast, xm_rvalid, xm_rready;

    axi_xbar_mm u_xbar_mm (
        .aclk           (axi_aclk),
        .aresetn        (axi_aresetn),
        .s_axi_awid     (mm_awid),
        .s_axi_awaddr   (mm_awaddr),
        .s_axi_awlen    (mm_awlen),
        .s_axi_awsize   (mm_awsize),
        .s_axi_awburst  (mm_awburst),
        .s_axi_awlock   (mm_awlock),
        .s_axi_awcache  (mm_awcache),
        .s_axi_awprot   (mm_awprot),
        .s_axi_awqos    (4'b0),
        .s_axi_awvalid  (mm_awvalid),
        .s_axi_awready  (mm_awready),
        .s_axi_wdata    (mm_wdata),
        .s_axi_wstrb    (mm_wstrb),
        .s_axi_wlast    (mm_wlast),
        .s_axi_wvalid   (mm_wvalid),
        .s_axi_wready   (mm_wready),
        .s_axi_bid      (mm_bid),
        .s_axi_bresp    (mm_bresp),
        .s_axi_bvalid   (mm_bvalid),
        .s_axi_bready   (mm_bready),
        .s_axi_arid     (mm_arid),
        .s_axi_araddr   (mm_araddr),
        .s_axi_arlen    (mm_arlen),
        .s_axi_arsize   (mm_arsize),
        .s_axi_arburst  (mm_arburst),
        .s_axi_arlock   (mm_arlock),
        .s_axi_arcache  (mm_arcache),
        .s_axi_arprot   (mm_arprot),
        .s_axi_arqos    (4'b0),
        .s_axi_arvalid  (mm_arvalid),
        .s_axi_arready  (mm_arready),
        .s_axi_rid      (mm_rid),
        .s_axi_rdata    (mm_rdata),
        .s_axi_rresp    (mm_rresp),
        .s_axi_rlast    (mm_rlast),
        .s_axi_rvalid   (mm_rvalid),
        .s_axi_rready   (mm_rready),

        .m_axi_awid     (xm_awid),
        .m_axi_awaddr   (xm_awaddr),
        .m_axi_awlen    (xm_awlen),
        .m_axi_awsize   (xm_awsize),
        .m_axi_awburst  (xm_awburst),
        .m_axi_awlock   (xm_awlock),
        .m_axi_awcache  (xm_awcache),
        .m_axi_awprot   (xm_awprot),
        .m_axi_awregion (),
        .m_axi_awqos    (),
        .m_axi_awvalid  (xm_awvalid),
        .m_axi_awready  (xm_awready),
        .m_axi_wdata    (xm_wdata),
        .m_axi_wstrb    (xm_wstrb),
        .m_axi_wlast    (xm_wlast),
        .m_axi_wvalid   (xm_wvalid),
        .m_axi_wready   (xm_wready),
        .m_axi_bid      (xm_bid),
        .m_axi_bresp    (xm_bresp),
        .m_axi_bvalid   (xm_bvalid),
        .m_axi_bready   (xm_bready),
        .m_axi_arid     (xm_arid),
        .m_axi_araddr   (xm_araddr),
        .m_axi_arlen    (xm_arlen),
        .m_axi_arsize   (xm_arsize),
        .m_axi_arburst  (xm_arburst),
        .m_axi_arlock   (xm_arlock),
        .m_axi_arcache  (xm_arcache),
        .m_axi_arprot   (xm_arprot),
        .m_axi_arregion (),
        .m_axi_arqos    (),
        .m_axi_arvalid  (xm_arvalid),
        .m_axi_arready  (xm_arready),
        .m_axi_rid      (xm_rid),
        .m_axi_rdata    (xm_rdata),
        .m_axi_rresp    (xm_rresp),
        .m_axi_rlast    (xm_rlast),
        .m_axi_rvalid   (xm_rvalid),
        .m_axi_rready   (xm_rready)
    );

    wire         bram_clk, bram_en;
    wire [63:0]  bram_we;
    wire [15:0]  bram_addr;
    wire [511:0] bram_wrdata, bram_rddata;

    axi_bram_ctrl_0 u_bram_ctrl (
        .s_axi_aclk    (axi_aclk),
        .s_axi_aresetn (axi_aresetn),
        .s_axi_awid    (xm_awid),
        .s_axi_awaddr  (xm_awaddr[15:0]),
        .s_axi_awlen   (xm_awlen),
        .s_axi_awsize  (xm_awsize),
        .s_axi_awburst (xm_awburst),
        .s_axi_awlock  (xm_awlock),
        .s_axi_awcache (xm_awcache),
        .s_axi_awprot  (xm_awprot),
        .s_axi_awvalid (xm_awvalid),
        .s_axi_awready (xm_awready),
        .s_axi_wdata   (xm_wdata),
        .s_axi_wstrb   (xm_wstrb),
        .s_axi_wlast   (xm_wlast),
        .s_axi_wvalid  (xm_wvalid),
        .s_axi_wready  (xm_wready),
        .s_axi_bid     (xm_bid),
        .s_axi_bresp   (xm_bresp),
        .s_axi_bvalid  (xm_bvalid),
        .s_axi_bready  (xm_bready),
        .s_axi_arid    (xm_arid),
        .s_axi_araddr  (xm_araddr[15:0]),
        .s_axi_arlen   (xm_arlen),
        .s_axi_arsize  (xm_arsize),
        .s_axi_arburst (xm_arburst),
        .s_axi_arlock  (xm_arlock),
        .s_axi_arcache (xm_arcache),
        .s_axi_arprot  (xm_arprot),
        .s_axi_arvalid (xm_arvalid),
        .s_axi_arready (xm_arready),
        .s_axi_rid     (xm_rid),
        .s_axi_rdata   (xm_rdata),
        .s_axi_rresp   (xm_rresp),
        .s_axi_rlast   (xm_rlast),
        .s_axi_rvalid  (xm_rvalid),
        .s_axi_rready  (xm_rready),
        .bram_rst_a    (),
        .bram_clk_a    (bram_clk),
        .bram_en_a     (bram_en),
        .bram_we_a     (bram_we),
        .bram_addr_a   (bram_addr),
        .bram_wrdata_a (bram_wrdata),
        .bram_rddata_a (bram_rddata)
    );

    // A 512-bit word is 64 bytes, so the controller's low six address bits are always
    // zero. Passing the byte address straight through would use one sixty-fourth of the
    // memory and alias the rest.
    blk_mem_bram u_bram (
        .clka  (bram_clk),
        .ena   (bram_en),
        .wea   (bram_we),
        .addra (bram_addr[15:6]),
        .dina  (bram_wrdata),
        .douta (bram_rddata)
    );

    // --------------------------------------------------------- register crossbar
    //
    //   index  address        slave
    //     0    0x0001_0000    configuration flash, through STARTUPE3
    //     1    0x0003_0000    GPIO: user LEDs, design identity
    //     2    0x0004_0000    debug bridge (XVC)
    //     3    0x0005_0000    cage 0 I2C
    //     4    0x0006_0000    cage 1 I2C
    //     5    0x0007_0000    GPIO: QSFP sideband
    //
    localparam integer LITE_N = 6;
    wire [LITE_N*32-1:0] xl_awaddr, xl_araddr, xl_wdata, xl_rdata;
    wire [LITE_N*3-1:0]  xl_awprot, xl_arprot;
    wire [LITE_N*4-1:0]  xl_wstrb;
    wire [LITE_N*2-1:0]  xl_bresp, xl_rresp;
    wire [LITE_N-1:0]    xl_awvalid, xl_awready, xl_wvalid, xl_wready;
    wire [LITE_N-1:0]    xl_bvalid, xl_bready, xl_arvalid, xl_arready;
    wire [LITE_N-1:0]    xl_rvalid, xl_rready;

    axi_xbar_lite u_xbar_lite (
        .aclk          (axi_aclk),
        .aresetn       (axi_aresetn),
        .s_axi_awaddr  (axil_awaddr),
        .s_axi_awprot  (axil_awprot),
        .s_axi_awvalid (axil_awvalid),
        .s_axi_awready (axil_awready),
        .s_axi_wdata   (axil_wdata),
        .s_axi_wstrb   (axil_wstrb),
        .s_axi_wvalid  (axil_wvalid),
        .s_axi_wready  (axil_wready),
        .s_axi_bresp   (axil_bresp),
        .s_axi_bvalid  (axil_bvalid),
        .s_axi_bready  (axil_bready),
        .s_axi_araddr  (axil_araddr),
        .s_axi_arprot  (axil_arprot),
        .s_axi_arvalid (axil_arvalid),
        .s_axi_arready (axil_arready),
        .s_axi_rdata   (axil_rdata),
        .s_axi_rresp   (axil_rresp),
        .s_axi_rvalid  (axil_rvalid),
        .s_axi_rready  (axil_rready),

        .m_axi_awaddr  (xl_awaddr),
        .m_axi_awprot  (xl_awprot),
        .m_axi_awvalid (xl_awvalid),
        .m_axi_awready (xl_awready),
        .m_axi_wdata   (xl_wdata),
        .m_axi_wstrb   (xl_wstrb),
        .m_axi_wvalid  (xl_wvalid),
        .m_axi_wready  (xl_wready),
        .m_axi_bresp   (xl_bresp),
        .m_axi_bvalid  (xl_bvalid),
        .m_axi_bready  (xl_bready),
        .m_axi_araddr  (xl_araddr),
        .m_axi_arprot  (xl_arprot),
        .m_axi_arvalid (xl_arvalid),
        .m_axi_arready (xl_arready),
        .m_axi_rdata   (xl_rdata),
        .m_axi_rresp   (xl_rresp),
        .m_axi_rvalid  (xl_rvalid),
        .m_axi_rready  (xl_rready)
    );

    // ------------------------------------------------- configuration flash, index 0
    // C_USE_STARTUP puts the controller behind STARTUPE3, so the flash is reached over
    // the dedicated configuration pins the device booted from. That is why no pin
    // constraint appears anywhere for this interface: those pins are not fabric I/O.
    //
    // The startup tie-offs are the ones the IP itself applies on 7-series parts, where
    // they are not exposed: GSR and GTS deasserted, CCLK driven, DONE left alone.
    wire spi_eos;

    axi_quad_spi_0 u_spi (
        .ext_spi_clk   (ext_spi_clk),
        .s_axi_aclk    (axi_aclk),
        .s_axi_aresetn (axi_aresetn),
        .s_axi_awaddr  (xl_awaddr[32*0 +: 7]),
        .s_axi_awvalid (xl_awvalid[0]),
        .s_axi_awready (xl_awready[0]),
        .s_axi_wdata   (xl_wdata[32*0 +: 32]),
        .s_axi_wstrb   (xl_wstrb[4*0 +: 4]),
        .s_axi_wvalid  (xl_wvalid[0]),
        .s_axi_wready  (xl_wready[0]),
        .s_axi_bresp   (xl_bresp[2*0 +: 2]),
        .s_axi_bvalid  (xl_bvalid[0]),
        .s_axi_bready  (xl_bready[0]),
        .s_axi_araddr  (xl_araddr[32*0 +: 7]),
        .s_axi_arvalid (xl_arvalid[0]),
        .s_axi_arready (xl_arready[0]),
        .s_axi_rdata   (xl_rdata[32*0 +: 32]),
        .s_axi_rresp   (xl_rresp[2*0 +: 2]),
        .s_axi_rvalid  (xl_rvalid[0]),
        .s_axi_rready  (xl_rready[0]),
        .cfgclk        (),
        .cfgmclk       (),
        .eos           (spi_eos),
        .preq          (),
        .gsr           (1'b0),
        .gts           (1'b0),
        .keyclearb     (1'b0),
        .usrcclkts     (1'b0),
        .usrdoneo      (1'b1),
        .usrdonets     (1'b1),
        .ip2intc_irpt  ()
    );

    // ------------------------------------------------ GPIO: LEDs and identity, index 1
    // Channel 2 returns a constant the host checks before it touches anything else, so
    // a test run against the wrong bitstream fails on the first read rather than by
    // misinterpreting registers that happen to exist at the same addresses.
    //
    // The low bit is End Of Startup from the SPI controller's STARTUPE3. It is always 1
    // on a configured device; carrying a real signal rather than a constant means the
    // identity read also proves the startup block is present and clocked.
    wire [31:0] design_status = {24'h42_4D_01, 7'b0, spi_eos};

    axi_gpio_led u_gpio (
        .s_axi_aclk    (axi_aclk),
        .s_axi_aresetn (axi_aresetn),
        .s_axi_awaddr  (xl_awaddr[32*1 +: 9]),
        .s_axi_awvalid (xl_awvalid[1]),
        .s_axi_awready (xl_awready[1]),
        .s_axi_wdata   (xl_wdata[32*1 +: 32]),
        .s_axi_wstrb   (xl_wstrb[4*1 +: 4]),
        .s_axi_wvalid  (xl_wvalid[1]),
        .s_axi_wready  (xl_wready[1]),
        .s_axi_bresp   (xl_bresp[2*1 +: 2]),
        .s_axi_bvalid  (xl_bvalid[1]),
        .s_axi_bready  (xl_bready[1]),
        .s_axi_araddr  (xl_araddr[32*1 +: 9]),
        .s_axi_arvalid (xl_arvalid[1]),
        .s_axi_arready (xl_arready[1]),
        .s_axi_rdata   (xl_rdata[32*1 +: 32]),
        .s_axi_rresp   (xl_rresp[2*1 +: 2]),
        .s_axi_rvalid  (xl_rvalid[1]),
        .s_axi_rready  (xl_rready[1]),
        .gpio_io_o     (user_led),
        .gpio2_io_i    (design_status)
    );

    // ------------------------------------------------------- XVC over PCIe, index 2
    debug_bridge_xvc u_xvc (
        .s_axi_aclk    (axi_aclk),
        .s_axi_aresetn (axi_aresetn),
        .S_AXI_awaddr  (xl_awaddr[32*2 +: 5]),
        .S_AXI_awprot  (xl_awprot[3*2 +: 3]),
        .S_AXI_awvalid (xl_awvalid[2]),
        .S_AXI_awready (xl_awready[2]),
        .S_AXI_wdata   (xl_wdata[32*2 +: 32]),
        .S_AXI_wstrb   (xl_wstrb[4*2 +: 4]),
        .S_AXI_wvalid  (xl_wvalid[2]),
        .S_AXI_wready  (xl_wready[2]),
        .S_AXI_bresp   (xl_bresp[2*2 +: 2]),
        .S_AXI_bvalid  (xl_bvalid[2]),
        .S_AXI_bready  (xl_bready[2]),
        .S_AXI_araddr  (xl_araddr[32*2 +: 5]),
        .S_AXI_arprot  (xl_arprot[3*2 +: 3]),
        .S_AXI_arvalid (xl_arvalid[2]),
        .S_AXI_arready (xl_arready[2]),
        .S_AXI_rdata   (xl_rdata[32*2 +: 32]),
        .S_AXI_rresp   (xl_rresp[2*2 +: 2]),
        .S_AXI_rvalid  (xl_rvalid[2]),
        .S_AXI_rready  (xl_rready[2])
    );

    // ------------------------------------------------ module I2C, indices 3 and 4
    // Open-drain on both lines: the controller only ever pulls low, and the board's
    // pull-ups supply the high level. Driving high actively would fight the module.
    wire [1:0] scl_i, scl_o, scl_t, sda_i, sda_o, sda_t;

    IOBUF u_scl0 (.I(scl_o[0]), .O(scl_i[0]), .T(scl_t[0]), .IO(qsfp0_i2c_scl));
    IOBUF u_sda0 (.I(sda_o[0]), .O(sda_i[0]), .T(sda_t[0]), .IO(qsfp0_i2c_sda));
    IOBUF u_scl1 (.I(scl_o[1]), .O(scl_i[1]), .T(scl_t[1]), .IO(qsfp1_i2c_scl));
    IOBUF u_sda1 (.I(sda_o[1]), .O(sda_i[1]), .T(sda_t[1]), .IO(qsfp1_i2c_sda));

    axi_iic_0 u_iic0 (
        .s_axi_aclk    (axi_aclk),
        .s_axi_aresetn (axi_aresetn),
        .iic2intc_irpt (),
        .s_axi_awaddr  (xl_awaddr[32*3 +: 9]),
        .s_axi_awvalid (xl_awvalid[3]),
        .s_axi_awready (xl_awready[3]),
        .s_axi_wdata   (xl_wdata[32*3 +: 32]),
        .s_axi_wstrb   (xl_wstrb[4*3 +: 4]),
        .s_axi_wvalid  (xl_wvalid[3]),
        .s_axi_wready  (xl_wready[3]),
        .s_axi_bresp   (xl_bresp[2*3 +: 2]),
        .s_axi_bvalid  (xl_bvalid[3]),
        .s_axi_bready  (xl_bready[3]),
        .s_axi_araddr  (xl_araddr[32*3 +: 9]),
        .s_axi_arvalid (xl_arvalid[3]),
        .s_axi_arready (xl_arready[3]),
        .s_axi_rdata   (xl_rdata[32*3 +: 32]),
        .s_axi_rresp   (xl_rresp[2*3 +: 2]),
        .s_axi_rvalid  (xl_rvalid[3]),
        .s_axi_rready  (xl_rready[3]),
        .sda_i         (sda_i[0]),
        .sda_o         (sda_o[0]),
        .sda_t         (sda_t[0]),
        .scl_i         (scl_i[0]),
        .scl_o         (scl_o[0]),
        .scl_t         (scl_t[0]),
        .gpo           ()
    );

    axi_iic_0 u_iic1 (
        .s_axi_aclk    (axi_aclk),
        .s_axi_aresetn (axi_aresetn),
        .iic2intc_irpt (),
        .s_axi_awaddr  (xl_awaddr[32*4 +: 9]),
        .s_axi_awvalid (xl_awvalid[4]),
        .s_axi_awready (xl_awready[4]),
        .s_axi_wdata   (xl_wdata[32*4 +: 32]),
        .s_axi_wstrb   (xl_wstrb[4*4 +: 4]),
        .s_axi_wvalid  (xl_wvalid[4]),
        .s_axi_wready  (xl_wready[4]),
        .s_axi_bresp   (xl_bresp[2*4 +: 2]),
        .s_axi_bvalid  (xl_bvalid[4]),
        .s_axi_bready  (xl_bready[4]),
        .s_axi_araddr  (xl_araddr[32*4 +: 9]),
        .s_axi_arvalid (xl_arvalid[4]),
        .s_axi_arready (xl_arready[4]),
        .s_axi_rdata   (xl_rdata[32*4 +: 32]),
        .s_axi_rresp   (xl_rresp[2*4 +: 2]),
        .s_axi_rvalid  (xl_rvalid[4]),
        .s_axi_rready  (xl_rready[4]),
        .sda_i         (sda_i[1]),
        .sda_o         (sda_o[1]),
        .sda_t         (sda_t[1]),
        .scl_i         (scl_i[1]),
        .scl_o         (scl_o[1]),
        .scl_t         (scl_t[1]),
        .gpo           ()
    );

    // ------------------------------------------------ GPIO: QSFP sideband, index 5
    // Channel 1, outputs, reset value 0x05 -- both ResetL high. That default matters:
    // between configuration and the host's first register write, this is what holds the
    // modules out of reset. A design that leaves these pins undeclared instead lets them
    // fall to the bitstream's UNUSEDPIN pulldown and holds both modules in reset
    // forever; see xdc/qsfp_sideband.xdc.
    //
    //   bit 0  cage 0 ResetL      bit 4  cage 0 yellow LED
    //   bit 1  cage 0 LPMode      bit 5  cage 1 yellow LED
    //   bit 2  cage 1 ResetL      bit 6  cage 0 green LED
    //   bit 3  cage 1 LPMode      bit 7  cage 1 green LED
    wire [7:0] sideband_out;
    assign {qsfp_led_g, qsfp_led_y, qsfp1_lpmode, qsfp1_resetl, qsfp0_lpmode, qsfp0_resetl}
           = sideband_out;

    // Channel 2, inputs. ModPrsL and IntL are asynchronous open-drain signals from the
    // module, so they get the usual two stages before anything reads them.
    (* ASYNC_REG = "TRUE" *) reg [1:0] prs0_sync = 2'b11, int0_sync = 2'b11;
    (* ASYNC_REG = "TRUE" *) reg [1:0] prs1_sync = 2'b11, int1_sync = 2'b11;
    always @(posedge axi_aclk) begin
        prs0_sync <= {prs0_sync[0], qsfp0_modprsl};
        int0_sync <= {int0_sync[0], qsfp0_intl};
        prs1_sync <= {prs1_sync[0], qsfp1_modprsl};
        int1_sync <= {int1_sync[0], qsfp1_intl};
    end

    //   bit 0  cage 0 ModPrsL, low when a module is seated
    //   bit 1  cage 0 IntL
    //   bit 2  cage 1 ModPrsL
    //   bit 3  cage 1 IntL
    wire [7:0] sideband_in = {4'b0, int1_sync[1], prs1_sync[1], int0_sync[1], prs0_sync[1]};

    axi_gpio_qsfp u_gpio_qsfp (
        .s_axi_aclk    (axi_aclk),
        .s_axi_aresetn (axi_aresetn),
        .s_axi_awaddr  (xl_awaddr[32*5 +: 9]),
        .s_axi_awvalid (xl_awvalid[5]),
        .s_axi_awready (xl_awready[5]),
        .s_axi_wdata   (xl_wdata[32*5 +: 32]),
        .s_axi_wstrb   (xl_wstrb[4*5 +: 4]),
        .s_axi_wvalid  (xl_wvalid[5]),
        .s_axi_wready  (xl_wready[5]),
        .s_axi_bresp   (xl_bresp[2*5 +: 2]),
        .s_axi_bvalid  (xl_bvalid[5]),
        .s_axi_bready  (xl_bready[5]),
        .s_axi_araddr  (xl_araddr[32*5 +: 9]),
        .s_axi_arvalid (xl_arvalid[5]),
        .s_axi_arready (xl_arready[5]),
        .s_axi_rdata   (xl_rdata[32*5 +: 32]),
        .s_axi_rresp   (xl_rresp[2*5 +: 2]),
        .s_axi_rvalid  (xl_rvalid[5]),
        .s_axi_rready  (xl_rready[5]),
        .gpio_io_o     (sideband_out),
        .gpio2_io_i    (sideband_in)
    );

endmodule

`default_nettype wire
