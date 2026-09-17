// PCIe bring-up design: XDMA x16 Gen3 with two DMA targets and a register window.
//
// The point of this design is to separate "does the PCIe link work" from everything
// else. No memory controllers, no transceivers other than the PCIe ones. If the host
// cannot see this design, the problem is PCIe.
//
// What it gives the host:
//
//   BRAM at 0xC000_0000, 64 KB    DMA target built from block RAM
//   URAM at 0xC001_0000, 64 KB    DMA target built from UltraRAM
//   GPIO at 0x0003_0000           eight user LEDs, plus an interrupt trigger
//   XVC  at 0x0004_0000           debug bridge, so Hardware Manager works over PCIe
//
// Two DMA targets rather than one because BRAM and URAM are different silicon with
// different timing, and a design that only exercises BRAM says nothing about whether
// URAM works. They are deliberately the same size and shape so the host can run the
// identical test against both and compare.
//
// The XVC bridge is what makes this worth flashing: with it, Hardware Manager reaches
// the device over PCIe, so DDR4 calibration and ILAs in *other* designs can be read
// without a JTAG cable attached.
//
// Everything is wired explicitly here rather than through a block design. Block designs
// carry a hard version gate and pinned IP versions that break on a toolchain upgrade;
// this file does not.

`default_nettype none

module golden_pcie_top (
    // PCIe edge connector.
    input  wire        pcie_refclk_p,
    input  wire        pcie_refclk_n,
    input  wire        pcie_perst_n,
    input  wire [15:0] pcie_rx_p,
    input  wire [15:0] pcie_rx_n,
    output wire [15:0] pcie_tx_p,
    output wire [15:0] pcie_tx_n,

    // Green LED at the bracket. Driven straight from the endpoint's link status, so it
    // tells you whether the link trained without any host software being involved.
    output wire        pcie_link_up,

    // Eight user LEDs, host-controlled through the GPIO.
    output wire [7:0]  user_led
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

    wire        usr_irq_req;
    wire        user_lnk_up;

    assign pcie_link_up = user_lnk_up;

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

    // ------------------------------------------------- memory-mapped crossbar
    // The crossbar presents its master side as concatenated vectors rather than named
    // ports: slave 0 occupies the low slice of each, slave 1 the next. Index 0 is BRAM,
    // index 1 is URAM.
    wire [7:0]    xm_awid,    xm_arid,    xm_bid,    xm_rid;
    wire [127:0]  xm_awaddr,  xm_araddr;
    wire [15:0]   xm_awlen,   xm_arlen;
    wire [5:0]    xm_awsize,  xm_arsize,  xm_awprot, xm_arprot;
    wire [3:0]    xm_awburst, xm_arburst, xm_bresp,  xm_rresp;
    wire [1:0]    xm_awlock,  xm_arlock;
    wire [7:0]    xm_awcache, xm_arcache;
    wire [1:0]    xm_awvalid, xm_awready, xm_arvalid, xm_arready;
    wire [1023:0] xm_wdata,   xm_rdata;
    wire [127:0]  xm_wstrb;
    wire [1:0]    xm_wlast,   xm_wvalid,  xm_wready;
    wire [1:0]    xm_bvalid,  xm_bready,  xm_rlast,  xm_rvalid, xm_rready;

    axi_xbar_mm u_xbar_mm (
        .aclk          (axi_aclk),
        .aresetn       (axi_aresetn),

        .s_axi_awid    (mm_awid),
        .s_axi_awaddr  (mm_awaddr),
        .s_axi_awlen   (mm_awlen),
        .s_axi_awsize  (mm_awsize),
        .s_axi_awburst (mm_awburst),
        .s_axi_awlock  (mm_awlock),
        .s_axi_awcache (mm_awcache),
        .s_axi_awprot  (mm_awprot),
        // XDMA does not drive QoS. Zero is "no priority stated", which is what it means.
        .s_axi_awqos   (4'b0),
        .s_axi_awvalid (mm_awvalid),
        .s_axi_awready (mm_awready),
        .s_axi_wdata   (mm_wdata),
        .s_axi_wstrb   (mm_wstrb),
        .s_axi_wlast   (mm_wlast),
        .s_axi_wvalid  (mm_wvalid),
        .s_axi_wready  (mm_wready),
        .s_axi_bid     (mm_bid),
        .s_axi_bresp   (mm_bresp),
        .s_axi_bvalid  (mm_bvalid),
        .s_axi_bready  (mm_bready),
        .s_axi_arid    (mm_arid),
        .s_axi_araddr  (mm_araddr),
        .s_axi_arlen   (mm_arlen),
        .s_axi_arsize  (mm_arsize),
        .s_axi_arburst (mm_arburst),
        .s_axi_arlock  (mm_arlock),
        .s_axi_arcache (mm_arcache),
        .s_axi_arprot  (mm_arprot),
        .s_axi_arqos   (4'b0),
        .s_axi_arvalid (mm_arvalid),
        .s_axi_arready (mm_arready),
        .s_axi_rid     (mm_rid),
        .s_axi_rdata   (mm_rdata),
        .s_axi_rresp   (mm_rresp),
        .s_axi_rlast   (mm_rlast),
        .s_axi_rvalid  (mm_rvalid),
        .s_axi_rready  (mm_rready),

        .m_axi_awid    (xm_awid),
        .m_axi_awaddr  (xm_awaddr),
        .m_axi_awlen   (xm_awlen),
        .m_axi_awsize  (xm_awsize),
        .m_axi_awburst (xm_awburst),
        .m_axi_awlock  (xm_awlock),
        .m_axi_awcache (xm_awcache),
        .m_axi_awprot  (xm_awprot),
        .m_axi_awregion(),
        .m_axi_awqos   (),
        .m_axi_awvalid (xm_awvalid),
        .m_axi_awready (xm_awready),
        .m_axi_wdata   (xm_wdata),
        .m_axi_wstrb   (xm_wstrb),
        .m_axi_wlast   (xm_wlast),
        .m_axi_wvalid  (xm_wvalid),
        .m_axi_wready  (xm_wready),
        .m_axi_bid     (xm_bid),
        .m_axi_bresp   (xm_bresp),
        .m_axi_bvalid  (xm_bvalid),
        .m_axi_bready  (xm_bready),
        .m_axi_arid    (xm_arid),
        .m_axi_araddr  (xm_araddr),
        .m_axi_arlen   (xm_arlen),
        .m_axi_arsize  (xm_arsize),
        .m_axi_arburst (xm_arburst),
        .m_axi_arlock  (xm_arlock),
        .m_axi_arcache (xm_arcache),
        .m_axi_arprot  (xm_arprot),
        .m_axi_arregion(),
        .m_axi_arqos   (),
        .m_axi_arvalid (xm_arvalid),
        .m_axi_arready (xm_arready),
        .m_axi_rid     (xm_rid),
        .m_axi_rdata   (xm_rdata),
        .m_axi_rresp   (xm_rresp),
        .m_axi_rlast   (xm_rlast),
        .m_axi_rvalid  (xm_rvalid),
        .m_axi_rready  (xm_rready)
    );

    // ------------------------------------------------------------- DMA targets
    // Two identical controllers, differing only in which memory primitive backs them.
    // The macro keeps them identical by construction, so a difference in results is a
    // difference in the silicon rather than in how they were wired.
    //
    // The ID signals have to be carried through. A BRAM controller generated with the
    // default ID width of zero has no ID ports at all, which leaves the crossbar's BID
    // and RID inputs undriven -- synthesis passes with a warning and opt_design then
    // fails deep inside the crossbar, complaining about a LUT input that connects to
    // nothing. The width must match the crossbar's.
    `define BRAM_TARGET(CTRL, MEM, IDX)                                    \
        wire        MEM``_clk;                                             \
        wire        MEM``_en;                                              \
        wire [63:0] MEM``_we;                                              \
        wire [15:0] MEM``_addr;                                            \
        wire [511:0] MEM``_wrdata, MEM``_rddata;                           \
        axi_bram_ctrl_0 CTRL (                                             \
            .s_axi_aclk    (axi_aclk),                                     \
            .s_axi_aresetn (axi_aresetn),                                  \
            .s_axi_awid    (xm_awid   [4*IDX   +: 4]),                     \
            .s_axi_awaddr  (xm_awaddr [64*IDX  +: 16]),                    \
            .s_axi_awlen   (xm_awlen  [8*IDX   +: 8]),                     \
            .s_axi_awsize  (xm_awsize [3*IDX   +: 3]),                     \
            .s_axi_awburst (xm_awburst[2*IDX   +: 2]),                     \
            .s_axi_awlock  (xm_awlock [IDX]),                              \
            .s_axi_awcache (xm_awcache[4*IDX   +: 4]),                     \
            .s_axi_awprot  (xm_awprot [3*IDX   +: 3]),                     \
            .s_axi_awvalid (xm_awvalid[IDX]),                              \
            .s_axi_awready (xm_awready[IDX]),                              \
            .s_axi_wdata   (xm_wdata  [512*IDX +: 512]),                   \
            .s_axi_wstrb   (xm_wstrb  [64*IDX  +: 64]),                    \
            .s_axi_wlast   (xm_wlast  [IDX]),                              \
            .s_axi_wvalid  (xm_wvalid [IDX]),                              \
            .s_axi_wready  (xm_wready [IDX]),                              \
            .s_axi_bid     (xm_bid    [4*IDX   +: 4]),                     \
            .s_axi_bresp   (xm_bresp  [2*IDX   +: 2]),                     \
            .s_axi_bvalid  (xm_bvalid [IDX]),                              \
            .s_axi_bready  (xm_bready [IDX]),                              \
            .s_axi_arid    (xm_arid   [4*IDX   +: 4]),                     \
            .s_axi_araddr  (xm_araddr [64*IDX  +: 16]),                    \
            .s_axi_arlen   (xm_arlen  [8*IDX   +: 8]),                     \
            .s_axi_arsize  (xm_arsize [3*IDX   +: 3]),                     \
            .s_axi_arburst (xm_arburst[2*IDX   +: 2]),                     \
            .s_axi_arlock  (xm_arlock [IDX]),                              \
            .s_axi_arcache (xm_arcache[4*IDX   +: 4]),                     \
            .s_axi_arprot  (xm_arprot [3*IDX   +: 3]),                     \
            .s_axi_arvalid (xm_arvalid[IDX]),                              \
            .s_axi_arready (xm_arready[IDX]),                              \
            .s_axi_rid     (xm_rid    [4*IDX   +: 4]),                     \
            .s_axi_rdata   (xm_rdata  [512*IDX +: 512]),                   \
            .s_axi_rresp   (xm_rresp  [2*IDX   +: 2]),                     \
            .s_axi_rlast   (xm_rlast  [IDX]),                              \
            .s_axi_rvalid  (xm_rvalid [IDX]),                              \
            .s_axi_rready  (xm_rready [IDX]),                              \
            .bram_rst_a    (),                                             \
            .bram_clk_a    (MEM``_clk),                                    \
            .bram_en_a     (MEM``_en),                                     \
            .bram_we_a     (MEM``_we),                                     \
            .bram_addr_a   (MEM``_addr),                                   \
            .bram_wrdata_a (MEM``_wrdata),                                 \
            .bram_rddata_a (MEM``_rddata)                                  \
        )

    `BRAM_TARGET(u_bram_ctrl, bram, 0);
    `BRAM_TARGET(u_uram_ctrl, uram, 1);

    `undef BRAM_TARGET

    // The controller emits a byte address; the memory takes a word address. A 512-bit
    // word is 64 bytes, so the low six bits are always zero and are dropped here. Wiring
    // the full byte address across would address one sixty-fourth of the memory and
    // alias the rest -- a fault that passes any test small enough to stay in the first
    // kilobyte.
    blk_mem_bram u_bram (
        .clka  (bram_clk),
        .ena   (bram_en),
        .wea   (bram_we),
        .addra (bram_addr[15:6]),
        .dina  (bram_wrdata),
        .douta (bram_rddata)
    );

    blk_mem_uram u_uram (
        .clka  (uram_clk),
        .ena   (uram_en),
        .wea   (uram_we),
        .addra (uram_addr[15:6]),
        .dina  (uram_wrdata),
        .douta (uram_rddata)
    );

    // --------------------------------------------------------- register crossbar
    wire [63:0] xl_awaddr, xl_araddr, xl_wdata, xl_rdata;
    wire [5:0]  xl_awprot, xl_arprot;
    wire [7:0]  xl_wstrb;
    wire [3:0]  xl_bresp,  xl_rresp;
    wire [1:0]  xl_awvalid, xl_awready, xl_wvalid, xl_wready;
    wire [1:0]  xl_bvalid, xl_bready, xl_arvalid, xl_arready;
    wire [1:0]  xl_rvalid, xl_rready;

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

    // ------------------------------------------------------- GPIO: LEDs and IRQ
    // Channel 1 drives the LEDs. Channel 2 is a single bit wired to the endpoint's user
    // interrupt request, which lets the host raise its own interrupt and then confirm it
    // arrived -- an end-to-end check of the interrupt path that needs no other hardware.
    // usr_irq_req is a level, so the host writes 1, waits for the event, then writes 0.
    wire [0:0] irq_trigger;
    assign usr_irq_req = irq_trigger[0];

    axi_gpio_led u_gpio (
        .s_axi_aclk    (axi_aclk),
        .s_axi_aresetn (axi_aresetn),
        .s_axi_awaddr  (xl_awaddr[0 +: 9]),
        .s_axi_awvalid (xl_awvalid[0]),
        .s_axi_awready (xl_awready[0]),
        .s_axi_wdata   (xl_wdata[0 +: 32]),
        .s_axi_wstrb   (xl_wstrb[0 +: 4]),
        .s_axi_wvalid  (xl_wvalid[0]),
        .s_axi_wready  (xl_wready[0]),
        .s_axi_bresp   (xl_bresp[0 +: 2]),
        .s_axi_bvalid  (xl_bvalid[0]),
        .s_axi_bready  (xl_bready[0]),
        .s_axi_araddr  (xl_araddr[0 +: 9]),
        .s_axi_arvalid (xl_arvalid[0]),
        .s_axi_arready (xl_arready[0]),
        .s_axi_rdata   (xl_rdata[0 +: 32]),
        .s_axi_rresp   (xl_rresp[0 +: 2]),
        .s_axi_rvalid  (xl_rvalid[0]),
        .s_axi_rready  (xl_rready[0]),
        .gpio_io_o     (user_led),
        .gpio2_io_o    (irq_trigger)
    );

    // ------------------------------------------------------------- XVC over PCIe
    // Turns the PCIe link into a JTAG cable. With this, xvc_pcie plus Hardware Manager
    // reaches the device with no physical cable attached.
    debug_bridge_xvc u_xvc (
        .s_axi_aclk    (axi_aclk),
        .s_axi_aresetn (axi_aresetn),
        .S_AXI_awaddr  (xl_awaddr[32 +: 5]),
        .S_AXI_awprot  (xl_awprot[3 +: 3]),
        .S_AXI_awvalid (xl_awvalid[1]),
        .S_AXI_awready (xl_awready[1]),
        .S_AXI_wdata   (xl_wdata[32 +: 32]),
        .S_AXI_wstrb   (xl_wstrb[4 +: 4]),
        .S_AXI_wvalid  (xl_wvalid[1]),
        .S_AXI_wready  (xl_wready[1]),
        .S_AXI_bresp   (xl_bresp[2 +: 2]),
        .S_AXI_bvalid  (xl_bvalid[1]),
        .S_AXI_bready  (xl_bready[1]),
        .S_AXI_araddr  (xl_araddr[32 +: 5]),
        .S_AXI_arprot  (xl_arprot[3 +: 3]),
        .S_AXI_arvalid (xl_arvalid[1]),
        .S_AXI_arready (xl_arready[1]),
        .S_AXI_rdata   (xl_rdata[32 +: 32]),
        .S_AXI_rresp   (xl_rresp[2 +: 2]),
        .S_AXI_rvalid  (xl_rvalid[1]),
        .S_AXI_rready  (xl_rready[1])
    );

endmodule

`default_nettype wire
