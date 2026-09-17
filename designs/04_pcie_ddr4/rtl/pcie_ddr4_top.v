// PCIe Gen3 DMA to 4 GiB ECC DDR4 on channel 1.
`default_nettype none

module pcie_ddr4_top (
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
    output wire [7:0]  user_led,
    // Channel 1 -- SLR1
    input  wire         c1_sys_clk_p,
    input  wire         c1_sys_clk_n,
    output wire [16:0]  c1_ddr4_adr,
    output wire [1:0]   c1_ddr4_ba,
    output wire [0:0]   c1_ddr4_bg,
    output wire [0:0]   c1_ddr4_cke,
    output wire [0:0]   c1_ddr4_odt,
    output wire [0:0]   c1_ddr4_cs_n,
    output wire         c1_ddr4_act_n,
    output wire         c1_ddr4_reset_n,
    output wire [0:0]   c1_ddr4_ck_t,
    output wire [0:0]   c1_ddr4_ck_c,
    inout  wire [71:0]  c1_ddr4_dq,
    inout  wire [8:0]   c1_ddr4_dqs_t,
    inout  wire [8:0]   c1_ddr4_dqs_c,
    inout  wire [8:0]   c1_ddr4_dm_dbi_n
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

    // Channel 1 is in the same SLR as the PCIe hard block.
    wire ui_clk, ui_rst, calibrated, ecc_irq;
    wire ecc_ready, ecc_failed;
    wire [31:0] ctrl_awaddr, ctrl_wdata;
    wire ctrl_awvalid, ctrl_awready, ctrl_wvalid, ctrl_wready, ctrl_bvalid, ctrl_bready;
    wire [1:0] ctrl_bresp;
    ecc_init u_ecc_init (
        .clk(ui_clk), .resetn(m_reset[3]), .calibrated(calibrated),
        .ready(ecc_ready), .failed(ecc_failed),
        .awaddr(ctrl_awaddr), .awvalid(ctrl_awvalid), .awready(ctrl_awready),
        .wdata(ctrl_wdata), .wvalid(ctrl_wvalid), .wready(ctrl_wready),
        .bresp(ctrl_bresp), .bvalid(ctrl_bvalid), .bready(ctrl_bready)
    );
    reg ecc_latched = 1'b0;
    always @(posedge ui_clk) begin
        if (ui_rst) ecc_latched <= 1'b0;
        else if (ecc_irq) ecc_latched <= 1'b1;
    end
    (* ASYNC_REG = "TRUE" *) reg [1:0] calib_sync = 0, ecc_sync = 0, ready_sync = 0, failed_sync = 0;
    always @(posedge axi_aclk) begin
        if (!axi_aresetn) begin calib_sync <= 0; ecc_sync <= 0; ready_sync <= 0; failed_sync <= 0; end
        else begin
            calib_sync <= {calib_sync[0], calibrated};
            ecc_sync <= {ecc_sync[0], ecc_latched};
            ready_sync <= {ready_sync[0], ecc_ready};
            failed_sync <= {failed_sync[0], ecc_failed};
        end
    end
    wire [31:0] design_status = {24'hD40101, 4'b0, failed_sync[1], ready_sync[1], ecc_sync[1], calib_sync[1]};
    // Asynchronous assertion and locally synchronized reset release in each domain.
    // Reset the transport on either PCIe reset or MIG UI reset; retrain MIG only
    // when the board's PERST is asserted, not on a host software DMA reset.
    wire transport_reset = !axi_aresetn || ui_rst;
    (* ASYNC_REG = "TRUE" *) reg [3:0] s_reset = 0, m_reset = 0;
    always @(posedge axi_aclk or posedge transport_reset)
        if (transport_reset) s_reset <= 0; else s_reset <= {s_reset[2:0], 1'b1};
    always @(posedge ui_clk or posedge transport_reset)
        if (transport_reset) m_reset <= 0; else m_reset <= {m_reset[2:0], 1'b1};
    wire [3:0] xm_awid;
    wire [63:0] xm_awaddr;
    wire [7:0] xm_awlen;
    wire [2:0] xm_awsize;
    wire [1:0] xm_awburst;
    wire xm_awlock;
    wire [3:0] xm_awcache;
    wire [2:0] xm_awprot;
    wire xm_awvalid;
    wire xm_awready;
    wire [3:0] xm_arid;
    wire [63:0] xm_araddr;
    wire [7:0] xm_arlen;
    wire [2:0] xm_arsize;
    wire [1:0] xm_arburst;
    wire xm_arlock;
    wire [3:0] xm_arcache;
    wire [2:0] xm_arprot;
    wire xm_arvalid;
    wire xm_arready;
    wire [511:0] xm_wdata;
    wire [63:0] xm_wstrb;
    wire xm_wlast;
    wire xm_wvalid;
    wire xm_wready;
    wire [3:0] xm_bid;
    wire [1:0] xm_bresp;
    wire xm_bvalid;
    wire xm_bready;
    wire [3:0] xm_rid;
    wire [511:0] xm_rdata;
    wire [1:0] xm_rresp;
    wire xm_rlast;
    wire xm_rvalid;
    wire xm_rready;
    wire [3:0] dd_awid;
    wire [63:0] dd_awaddr;
    wire [7:0] dd_awlen;
    wire [2:0] dd_awsize;
    wire [1:0] dd_awburst;
    wire dd_awlock;
    wire [3:0] dd_awcache;
    wire [2:0] dd_awprot;
    wire dd_awvalid;
    wire dd_awready;
    wire [3:0] dd_arid;
    wire [63:0] dd_araddr;
    wire [7:0] dd_arlen;
    wire [2:0] dd_arsize;
    wire [1:0] dd_arburst;
    wire dd_arlock;
    wire [3:0] dd_arcache;
    wire [2:0] dd_arprot;
    wire dd_arvalid;
    wire dd_arready;
    wire [511:0] dd_wdata;
    wire [63:0] dd_wstrb;
    wire dd_wlast;
    wire dd_wvalid;
    wire dd_wready;
    wire [3:0] dd_bid;
    wire [1:0] dd_bresp;
    wire dd_bvalid;
    wire dd_bready;
    wire [3:0] dd_rid;
    wire [511:0] dd_rdata;
    wire [1:0] dd_rresp;
    wire dd_rlast;
    wire dd_rvalid;
    wire dd_rready;
    axi_xbar_mm u_xbar_mm (
        .aclk          (axi_aclk),
        .aresetn       (s_reset[3]),

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

    axi_clock_converter_0 u_cdc (
        .s_axi_aclk(axi_aclk),
        .s_axi_aresetn(s_reset[3]),
        .m_axi_aclk(ui_clk),
        .m_axi_aresetn(m_reset[3]),
        .s_axi_awid(xm_awid),
        .s_axi_awaddr(xm_awaddr),
        .s_axi_awlen(xm_awlen),
        .s_axi_awsize(xm_awsize),
        .s_axi_awburst(xm_awburst),
        .s_axi_awlock(xm_awlock),
        .s_axi_awcache(xm_awcache),
        .s_axi_awprot(xm_awprot),
        .s_axi_awvalid(xm_awvalid),
        .s_axi_awready(xm_awready),
        .s_axi_arid(xm_arid),
        .s_axi_araddr(xm_araddr),
        .s_axi_arlen(xm_arlen),
        .s_axi_arsize(xm_arsize),
        .s_axi_arburst(xm_arburst),
        .s_axi_arlock(xm_arlock),
        .s_axi_arcache(xm_arcache),
        .s_axi_arprot(xm_arprot),
        .s_axi_arvalid(xm_arvalid),
        .s_axi_arready(xm_arready),
        .s_axi_wdata(xm_wdata),
        .s_axi_wstrb(xm_wstrb),
        .s_axi_wlast(xm_wlast),
        .s_axi_wvalid(xm_wvalid),
        .s_axi_wready(xm_wready),
        .s_axi_bid(xm_bid),
        .s_axi_bresp(xm_bresp),
        .s_axi_bvalid(xm_bvalid),
        .s_axi_bready(xm_bready),
        .s_axi_rid(xm_rid),
        .s_axi_rdata(xm_rdata),
        .s_axi_rresp(xm_rresp),
        .s_axi_rlast(xm_rlast),
        .s_axi_rvalid(xm_rvalid),
        .s_axi_rready(xm_rready),
        .m_axi_awid(dd_awid),
        .m_axi_awaddr(dd_awaddr),
        .m_axi_awlen(dd_awlen),
        .m_axi_awsize(dd_awsize),
        .m_axi_awburst(dd_awburst),
        .m_axi_awlock(dd_awlock),
        .m_axi_awcache(dd_awcache),
        .m_axi_awprot(dd_awprot),
        .m_axi_awvalid(dd_awvalid),
        .m_axi_awready(dd_awready),
        .m_axi_arid(dd_arid),
        .m_axi_araddr(dd_araddr),
        .m_axi_arlen(dd_arlen),
        .m_axi_arsize(dd_arsize),
        .m_axi_arburst(dd_arburst),
        .m_axi_arlock(dd_arlock),
        .m_axi_arcache(dd_arcache),
        .m_axi_arprot(dd_arprot),
        .m_axi_arvalid(dd_arvalid),
        .m_axi_arready(dd_arready),
        .m_axi_wdata(dd_wdata),
        .m_axi_wstrb(dd_wstrb),
        .m_axi_wlast(dd_wlast),
        .m_axi_wvalid(dd_wvalid),
        .m_axi_wready(dd_wready),
        .m_axi_bid(dd_bid),
        .m_axi_bresp(dd_bresp),
        .m_axi_bvalid(dd_bvalid),
        .m_axi_bready(dd_bready),
        .m_axi_rid(dd_rid),
        .m_axi_rdata(dd_rdata),
        .m_axi_rresp(dd_rresp),
        .m_axi_rlast(dd_rlast),
        .m_axi_rvalid(dd_rvalid),
        .m_axi_rready(dd_rready),
        .s_axi_awqos(4'b0),
        .s_axi_arqos(4'b0),
        .s_axi_awregion(4'b0),
        .s_axi_arregion(4'b0),
        .m_axi_awqos(),
        .m_axi_arqos(),
        .m_axi_awregion(),
        .m_axi_arregion()
    );
    ddr4_0 u_ddr4_c1 (
        .sys_rst(!pcie_perst_n),
        .c0_sys_clk_p(c1_sys_clk_p),
        .c0_sys_clk_n(c1_sys_clk_n),
        .c0_init_calib_complete(calibrated),
        .c0_ddr4_ui_clk(ui_clk),
        .c0_ddr4_ui_clk_sync_rst(ui_rst),
        .c0_ddr4_aresetn(m_reset[3]),
        .c0_ddr4_interrupt(ecc_irq),
        .c0_ddr4_adr(c1_ddr4_adr),
        .c0_ddr4_ba(c1_ddr4_ba),
        .c0_ddr4_bg(c1_ddr4_bg),
        .c0_ddr4_cke(c1_ddr4_cke),
        .c0_ddr4_odt(c1_ddr4_odt),
        .c0_ddr4_cs_n(c1_ddr4_cs_n),
        .c0_ddr4_act_n(c1_ddr4_act_n),
        .c0_ddr4_reset_n(c1_ddr4_reset_n),
        .c0_ddr4_ck_t(c1_ddr4_ck_t),
        .c0_ddr4_ck_c(c1_ddr4_ck_c),
        .c0_ddr4_dq(c1_ddr4_dq),
        .c0_ddr4_dqs_t(c1_ddr4_dqs_t),
        .c0_ddr4_dqs_c(c1_ddr4_dqs_c),
        .c0_ddr4_dm_dbi_n(c1_ddr4_dm_dbi_n),
        .c0_ddr4_s_axi_awid(dd_awid),
        .c0_ddr4_s_axi_awaddr(dd_awaddr[31:0]),
        .c0_ddr4_s_axi_awlen(dd_awlen),
        .c0_ddr4_s_axi_awsize(dd_awsize),
        .c0_ddr4_s_axi_awburst(dd_awburst),
        .c0_ddr4_s_axi_awlock(dd_awlock),
        .c0_ddr4_s_axi_awcache(dd_awcache),
        .c0_ddr4_s_axi_awprot(dd_awprot),
        .c0_ddr4_s_axi_awvalid(dd_awvalid),
        .c0_ddr4_s_axi_awready(dd_awready),
        .c0_ddr4_s_axi_arid(dd_arid),
        .c0_ddr4_s_axi_araddr(dd_araddr[31:0]),
        .c0_ddr4_s_axi_arlen(dd_arlen),
        .c0_ddr4_s_axi_arsize(dd_arsize),
        .c0_ddr4_s_axi_arburst(dd_arburst),
        .c0_ddr4_s_axi_arlock(dd_arlock),
        .c0_ddr4_s_axi_arcache(dd_arcache),
        .c0_ddr4_s_axi_arprot(dd_arprot),
        .c0_ddr4_s_axi_arvalid(dd_arvalid),
        .c0_ddr4_s_axi_arready(dd_arready),
        .c0_ddr4_s_axi_wdata(dd_wdata),
        .c0_ddr4_s_axi_wstrb(dd_wstrb),
        .c0_ddr4_s_axi_wlast(dd_wlast),
        .c0_ddr4_s_axi_wvalid(dd_wvalid),
        .c0_ddr4_s_axi_wready(dd_wready),
        .c0_ddr4_s_axi_bid(dd_bid),
        .c0_ddr4_s_axi_bresp(dd_bresp),
        .c0_ddr4_s_axi_bvalid(dd_bvalid),
        .c0_ddr4_s_axi_bready(dd_bready),
        .c0_ddr4_s_axi_rid(dd_rid),
        .c0_ddr4_s_axi_rdata(dd_rdata),
        .c0_ddr4_s_axi_rresp(dd_rresp),
        .c0_ddr4_s_axi_rlast(dd_rlast),
        .c0_ddr4_s_axi_rvalid(dd_rvalid),
        .c0_ddr4_s_axi_rready(dd_rready),
        .c0_ddr4_s_axi_awqos(4'b0),
        .c0_ddr4_s_axi_arqos(4'b0),
        .c0_ddr4_s_axi_ctrl_awvalid(ctrl_awvalid),
        .c0_ddr4_s_axi_ctrl_wvalid(ctrl_wvalid),
        .c0_ddr4_s_axi_ctrl_arvalid(1'b0),
        .c0_ddr4_s_axi_ctrl_awaddr(ctrl_awaddr),
        .c0_ddr4_s_axi_ctrl_araddr(32'b0),
        .c0_ddr4_s_axi_ctrl_wdata(ctrl_wdata),
        .c0_ddr4_s_axi_ctrl_bready(ctrl_bready),
        .c0_ddr4_s_axi_ctrl_awready(ctrl_awready),
        .c0_ddr4_s_axi_ctrl_wready(ctrl_wready),
        .c0_ddr4_s_axi_ctrl_bvalid(ctrl_bvalid),
        .c0_ddr4_s_axi_ctrl_bresp(ctrl_bresp),
        .c0_ddr4_s_axi_ctrl_rready(1'b1)
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
    // Channel 1 drives LEDs; channel 2 returns design identity and status.
    assign usr_irq_req = 1'b0;

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
        .gpio2_io_i    (design_status)
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
