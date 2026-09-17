// PCIe streaming loopback with 64 KiB FIFO and packet metadata.
`default_nettype none

module pcie_stream_top (
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

    wire [511:0] h2c_data, c2h_data;
    wire [63:0] h2c_keep, c2h_keep;
    wire h2c_last, h2c_valid, h2c_ready, c2h_last, c2h_valid, c2h_ready;
    wire [31:0] design_status = 32'h53540101;
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

        .m_axis_h2c_tdata_0(h2c_data),
        .m_axis_h2c_tkeep_0(h2c_keep),
        .m_axis_h2c_tlast_0(h2c_last),
        .m_axis_h2c_tvalid_0(h2c_valid),
        .m_axis_h2c_tready_0(h2c_ready),
        .s_axis_c2h_tdata_0(c2h_data),
        .s_axis_c2h_tkeep_0(c2h_keep),
        .s_axis_c2h_tlast_0(c2h_last),
        .s_axis_c2h_tvalid_0(c2h_valid),
        .s_axis_c2h_tready_0(c2h_ready),

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

    axis_data_fifo_0 u_fifo (
        .s_axis_aclk(axi_aclk),
        .s_axis_aresetn(axi_aresetn),
        .s_axis_tdata(h2c_data),
        .s_axis_tkeep(h2c_keep),
        .s_axis_tlast(h2c_last),
        .s_axis_tvalid(h2c_valid),
        .s_axis_tready(h2c_ready),
        .m_axis_tdata(c2h_data),
        .m_axis_tkeep(c2h_keep),
        .m_axis_tlast(c2h_last),
        .m_axis_tvalid(c2h_valid),
        .m_axis_tready(c2h_ready)
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
