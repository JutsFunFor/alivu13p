// Four-channel DDR4 bring-up: calibrate every channel, then prove each one stores data.
//
// No PCIe here on purpose. This design answers "does the memory work" without depending
// on the host interface, so a failure is unambiguous -- on a board where both are being
// brought up at once, a DMA test that fails tells you nothing about which half is wrong.
//
// Readout is through a VIO, so the whole thing is observable in Hardware Manager over
// JTAG with no host software at all.
//
// Two levels of evidence, because they fail differently:
//
//   calib_complete  the controller trained against the DRAM. This is what
//                   tools/check_ddr4_cal.tcl reads out of the MIG directly, and it
//                   already passes on this board.
//   bist pass       data written through the AXI port reads back correctly. Calibration
//                   can succeed on a channel that still corrupts data -- a swapped
//                   address line trains fine and then aliases.
//
// All four MIG instances come from one IP configuration, so they share a module and
// differ only in which external pins they drive.

`default_nettype none

module ddr4_cal_top (
    // 100 MHz board clock, bank 64. Reference clock for the VIO / debug hub only; each
    // memory channel has its own ~400 MHz reference.
    input  wire         sysclk_p,
    input  wire         sysclk_n,

    // Channel 0 -- SLR0
    input  wire         c0_sys_clk_p,
    input  wire         c0_sys_clk_n,
    output wire [16:0]  c0_ddr4_adr,
    output wire [1:0]   c0_ddr4_ba,
    output wire [0:0]   c0_ddr4_bg,
    output wire [0:0]   c0_ddr4_cke,
    output wire [0:0]   c0_ddr4_odt,
    output wire [0:0]   c0_ddr4_cs_n,
    output wire         c0_ddr4_act_n,
    output wire         c0_ddr4_reset_n,
    output wire [0:0]   c0_ddr4_ck_t,
    output wire [0:0]   c0_ddr4_ck_c,
    inout  wire [71:0]  c0_ddr4_dq,
    inout  wire [8:0]   c0_ddr4_dqs_t,
    inout  wire [8:0]   c0_ddr4_dqs_c,
    inout  wire [8:0]   c0_ddr4_dm_dbi_n,

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
    inout  wire [8:0]   c1_ddr4_dm_dbi_n,

    // Channel 2 -- SLR2
    input  wire         c2_sys_clk_p,
    input  wire         c2_sys_clk_n,
    output wire [16:0]  c2_ddr4_adr,
    output wire [1:0]   c2_ddr4_ba,
    output wire [0:0]   c2_ddr4_bg,
    output wire [0:0]   c2_ddr4_cke,
    output wire [0:0]   c2_ddr4_odt,
    output wire [0:0]   c2_ddr4_cs_n,
    output wire         c2_ddr4_act_n,
    output wire         c2_ddr4_reset_n,
    output wire [0:0]   c2_ddr4_ck_t,
    output wire [0:0]   c2_ddr4_ck_c,
    inout  wire [71:0]  c2_ddr4_dq,
    inout  wire [8:0]   c2_ddr4_dqs_t,
    inout  wire [8:0]   c2_ddr4_dqs_c,
    inout  wire [8:0]   c2_ddr4_dm_dbi_n,

    // Channel 3 -- SLR3
    input  wire         c3_sys_clk_p,
    input  wire         c3_sys_clk_n,
    output wire [16:0]  c3_ddr4_adr,
    output wire [1:0]   c3_ddr4_ba,
    output wire [0:0]   c3_ddr4_bg,
    output wire [0:0]   c3_ddr4_cke,
    output wire [0:0]   c3_ddr4_odt,
    output wire [0:0]   c3_ddr4_cs_n,
    output wire         c3_ddr4_act_n,
    output wire         c3_ddr4_reset_n,
    output wire [0:0]   c3_ddr4_ck_t,
    output wire [0:0]   c3_ddr4_ck_c,
    inout  wire [71:0]  c3_ddr4_dq,
    inout  wire [8:0]   c3_ddr4_dqs_t,
    inout  wire [8:0]   c3_ddr4_dqs_c,
    inout  wire [8:0]   c3_ddr4_dm_dbi_n,

    // QSFP module control, held inactive so nothing sits in reset. See docs/board-facts.md.
    // Status without a computer attached: low nibble is per-channel calibration, high
    // nibble is per-channel BIST pass. Enough to read the result of the whole test off
    // the card by eye, which is the only readout available if JTAG is busy or absent.
    output wire [7:0]   user_led
);

    localparam integer N_CH   = 4;
    localparam integer ADDR_W = 32;
    localparam integer DATA_W = 512;
    localparam integer ID_W   = 1;

    // ------------------------------------------------------------------ reference
    wire sysclk_ibuf, sysclk;
    IBUFGDS #(.DIFF_TERM("FALSE"), .IBUF_LOW_PWR("FALSE")) u_sysclk_ibuf (
        .I(sysclk_p), .IB(sysclk_n), .O(sysclk_ibuf));
    BUFG u_sysclk_bufg (.I(sysclk_ibuf), .O(sysclk));

    // sys_rst is active high on this IP -- confirmed against a working reference design
    // for this board, where it is driven from a MicroBlaze Debug_SYS_Rst.
    //
    // Held for 2^16 cycles, about 650 us. The controller resynchronises this internally
    // so a short pulse would probably do, but the reset only happens once at power-on
    // and nothing waits on it, so there is no reason to be stingy.
    reg [16:0] rst_cnt = 17'd0;
    always @(posedge sysclk) if (!rst_cnt[16]) rst_cnt <= rst_cnt + 1'b1;
    wire sys_rst = !rst_cnt[16];

    // ------------------------------------------------------- per-channel plumbing
    wire [N_CH-1:0]        calib_complete;
    wire [N_CH-1:0]        ecc_irq_raw;    // straight off the controller
    wire [N_CH-1:0]        ecc_interrupt;  // latched, in the ui_clk domain
    wire [N_CH-1:0]        bist_done, bist_pass, bist_busy;
    wire [32*N_CH-1:0]     bist_errors;
    wire [ADDR_W*N_CH-1:0] bist_first_bad;

    wire                   vio_start;
    wire [N_CH-1:0]        ui_clk, ui_rst;

    // AXI, flattened per channel.
    wire [ID_W*N_CH-1:0]     awid, arid;
    wire [ADDR_W*N_CH-1:0]   awaddr, araddr;
    wire [8*N_CH-1:0]        awlen, arlen;
    wire [3*N_CH-1:0]        awsize, arsize;
    wire [2*N_CH-1:0]        awburst, arburst;
    wire [N_CH-1:0]          awvalid, awready, arvalid, arready;
    wire [DATA_W*N_CH-1:0]   wdata, rdata;
    wire [(DATA_W/8)*N_CH-1:0] wstrb;
    wire [N_CH-1:0]          wlast, wvalid, wready;
    wire [2*N_CH-1:0]        bresp, rresp;
    wire [N_CH-1:0]          bvalid, bready, rvalid, rready, rlast;

    genvar c;
    generate
        for (c = 0; c < N_CH; c = c + 1) begin : gen_bist
            // The BIST lives in its channel's ui_clk domain, which is where the MIG's
            // AXI port is. Each channel has its own PLL, so these are four unrelated
            // domains, and the VIO runs on a fifth. Every signal that crosses between
            // them goes through a synchroniser rather than straight into logic.
            //
            // The start command comes from the VIO in the sysclk domain. It is a level,
            // not a pulse, so a two-flop synchroniser is all it needs; the BIST latches
            // it only when idle.
            (* ASYNC_REG = "TRUE" *) reg [1:0] start_sync;
            always @(posedge ui_clk[c]) start_sync <= {start_sync[0], vio_start};

            // Uncorrectable ECC errors arrive as a pulse on the controller's interrupt
            // line. Latch it: a pulse a few clocks wide is invisible to a VIO, which
            // samples on demand, so without this the most interesting failure the memory
            // can produce would leave no trace.
            reg ecc_latched;
            always @(posedge ui_clk[c]) begin
                if (ui_rst[c])             ecc_latched <= 1'b0;
                else if (ecc_irq_raw[c])   ecc_latched <= 1'b1;
            end
            assign ecc_interrupt[c] = ecc_latched;

            axi_bist #(
                .ADDR_W (ADDR_W),
                .DATA_W (DATA_W),
                .ID_W   (ID_W)
            ) u_bist (
                .clk            (ui_clk[c]),
                .rst            (ui_rst[c] || !calib_complete[c]),
                .start          (start_sync[1] && calib_complete[c]),
                .busy           (bist_busy[c]),
                .done           (bist_done[c]),
                .pass           (bist_pass[c]),
                .error_count    (bist_errors[32*c +: 32]),
                .first_bad_addr (bist_first_bad[ADDR_W*c +: ADDR_W]),

                .m_axi_awid   (awid   [ID_W*c   +: ID_W]),
                .m_axi_awaddr (awaddr [ADDR_W*c +: ADDR_W]),
                .m_axi_awlen  (awlen  [8*c      +: 8]),
                .m_axi_awsize (awsize [3*c      +: 3]),
                .m_axi_awburst(awburst[2*c      +: 2]),
                .m_axi_awvalid(awvalid[c]),
                .m_axi_awready(awready[c]),
                .m_axi_wdata  (wdata  [DATA_W*c +: DATA_W]),
                .m_axi_wstrb  (wstrb  [(DATA_W/8)*c +: DATA_W/8]),
                .m_axi_wlast  (wlast  [c]),
                .m_axi_wvalid (wvalid [c]),
                .m_axi_wready (wready [c]),
                .m_axi_bresp  (bresp  [2*c      +: 2]),
                .m_axi_bvalid (bvalid [c]),
                .m_axi_bready (bready [c]),
                .m_axi_arid   (arid   [ID_W*c   +: ID_W]),
                .m_axi_araddr (araddr [ADDR_W*c +: ADDR_W]),
                .m_axi_arlen  (arlen  [8*c      +: 8]),
                .m_axi_arsize (arsize [3*c      +: 3]),
                .m_axi_arburst(arburst[2*c      +: 2]),
                .m_axi_arvalid(arvalid[c]),
                .m_axi_arready(arready[c]),
                .m_axi_rdata  (rdata  [DATA_W*c +: DATA_W]),
                .m_axi_rresp  (rresp  [2*c      +: 2]),
                .m_axi_rlast  (rlast  [c]),
                .m_axi_rvalid (rvalid [c]),
                .m_axi_rready (rready [c])
            );
        end
    endgenerate

    // A macro keeps the four MIG instantiations honest: they are identical apart from
    // which pin group and which slice of the flattened AXI bundle they attach to, so
    // writing them out four times by hand invites a transposed index that synthesises
    // cleanly and fails only on hardware.
    `define DDR4_CH(INST, N)                                       \
        ddr4_0 INST (                                              \
            .sys_rst                  (sys_rst),                   \
            .c0_sys_clk_p             (c``N``_sys_clk_p),          \
            .c0_sys_clk_n             (c``N``_sys_clk_n),          \
            .c0_ddr4_adr              (c``N``_ddr4_adr),           \
            .c0_ddr4_ba               (c``N``_ddr4_ba),            \
            .c0_ddr4_bg               (c``N``_ddr4_bg),            \
            .c0_ddr4_cke              (c``N``_ddr4_cke),           \
            .c0_ddr4_odt              (c``N``_ddr4_odt),           \
            .c0_ddr4_cs_n             (c``N``_ddr4_cs_n),          \
            .c0_ddr4_act_n            (c``N``_ddr4_act_n),         \
            .c0_ddr4_reset_n          (c``N``_ddr4_reset_n),       \
            .c0_ddr4_ck_t             (c``N``_ddr4_ck_t),          \
            .c0_ddr4_ck_c             (c``N``_ddr4_ck_c),          \
            .c0_ddr4_dq               (c``N``_ddr4_dq),            \
            .c0_ddr4_dqs_t            (c``N``_ddr4_dqs_t),         \
            .c0_ddr4_dqs_c            (c``N``_ddr4_dqs_c),         \
            .c0_ddr4_dm_dbi_n         (c``N``_ddr4_dm_dbi_n),      \
            .c0_init_calib_complete   (calib_complete[N]),         \
            .c0_ddr4_ui_clk           (ui_clk[N]),                 \
            .c0_ddr4_ui_clk_sync_rst  (ui_rst[N]),                 \
            .c0_ddr4_aresetn          (!ui_rst[N]),                \
            .c0_ddr4_s_axi_ctrl_awvalid(1'b0),                     \
            .c0_ddr4_s_axi_ctrl_awready(),                         \
            .c0_ddr4_s_axi_ctrl_awaddr(32'b0),                     \
            .c0_ddr4_s_axi_ctrl_wvalid(1'b0),                      \
            .c0_ddr4_s_axi_ctrl_wready(),                          \
            .c0_ddr4_s_axi_ctrl_wdata (32'b0),                     \
            .c0_ddr4_s_axi_ctrl_bvalid(),                          \
            .c0_ddr4_s_axi_ctrl_bready(1'b1),                      \
            .c0_ddr4_s_axi_ctrl_bresp (),                          \
            .c0_ddr4_s_axi_ctrl_arvalid(1'b0),                     \
            .c0_ddr4_s_axi_ctrl_arready(),                         \
            .c0_ddr4_s_axi_ctrl_araddr(32'b0),                     \
            .c0_ddr4_s_axi_ctrl_rvalid(),                          \
            .c0_ddr4_s_axi_ctrl_rready(1'b1),                      \
            .c0_ddr4_s_axi_ctrl_rdata (),                          \
            .c0_ddr4_s_axi_ctrl_rresp (),                          \
            .c0_ddr4_interrupt        (ecc_irq_raw[N]),            \
            .c0_ddr4_s_axi_awid       (awid   [ID_W*N   +: ID_W]), \
            .c0_ddr4_s_axi_awaddr     (awaddr [ADDR_W*N +: ADDR_W]),\
            .c0_ddr4_s_axi_awlen      (awlen  [8*N      +: 8]),    \
            .c0_ddr4_s_axi_awsize     (awsize [3*N      +: 3]),    \
            .c0_ddr4_s_axi_awburst    (awburst[2*N      +: 2]),    \
            .c0_ddr4_s_axi_awlock     (1'b0),                      \
            .c0_ddr4_s_axi_awcache    (4'b0011),                   \
            .c0_ddr4_s_axi_awprot     (3'b000),                    \
            .c0_ddr4_s_axi_awqos      (4'b0000),                   \
            .c0_ddr4_s_axi_awvalid    (awvalid[N]),                \
            .c0_ddr4_s_axi_awready    (awready[N]),                \
            .c0_ddr4_s_axi_wdata      (wdata  [DATA_W*N +: DATA_W]),\
            .c0_ddr4_s_axi_wstrb      (wstrb  [(DATA_W/8)*N +: DATA_W/8]),\
            .c0_ddr4_s_axi_wlast      (wlast  [N]),                \
            .c0_ddr4_s_axi_wvalid     (wvalid [N]),                \
            .c0_ddr4_s_axi_wready     (wready [N]),                \
            .c0_ddr4_s_axi_bid        (),                          \
            .c0_ddr4_s_axi_bresp      (bresp  [2*N      +: 2]),    \
            .c0_ddr4_s_axi_bvalid     (bvalid [N]),                \
            .c0_ddr4_s_axi_bready     (bready [N]),                \
            .c0_ddr4_s_axi_arid       (arid   [ID_W*N   +: ID_W]), \
            .c0_ddr4_s_axi_araddr     (araddr [ADDR_W*N +: ADDR_W]),\
            .c0_ddr4_s_axi_arlen      (arlen  [8*N      +: 8]),    \
            .c0_ddr4_s_axi_arsize     (arsize [3*N      +: 3]),    \
            .c0_ddr4_s_axi_arburst    (arburst[2*N      +: 2]),    \
            .c0_ddr4_s_axi_arlock     (1'b0),                      \
            .c0_ddr4_s_axi_arcache    (4'b0011),                   \
            .c0_ddr4_s_axi_arprot     (3'b000),                    \
            .c0_ddr4_s_axi_arqos      (4'b0000),                   \
            .c0_ddr4_s_axi_arvalid    (arvalid[N]),                \
            .c0_ddr4_s_axi_arready    (arready[N]),                \
            .c0_ddr4_s_axi_rid        (),                          \
            .c0_ddr4_s_axi_rdata      (rdata  [DATA_W*N +: DATA_W]),\
            .c0_ddr4_s_axi_rresp      (rresp  [2*N      +: 2]),    \
            .c0_ddr4_s_axi_rlast      (rlast  [N]),                \
            .c0_ddr4_s_axi_rvalid     (rvalid [N]),                \
            .c0_ddr4_s_axi_rready     (rready [N])                 \
        )

    `DDR4_CH(u_ddr4_c0, 0);
    `DDR4_CH(u_ddr4_c1, 1);
    `DDR4_CH(u_ddr4_c2, 2);
    `DDR4_CH(u_ddr4_c3, 3);

    `undef DDR4_CH

    // ------------------------------------------------------------------- readout
    //
    // The VIO runs on sysclk, which is unrelated to all four ui_clk domains, so every
    // status signal is resynchronised here rather than being sampled raw. A VIO samples
    // whenever the user clicks refresh, so an unsynchronised multi-bit value can be
    // caught mid-change and read back as a number that never existed -- which on an
    // error counter is exactly the kind of wrong that gets believed.
    //
    // The single-bit flags go through two flops each. The wide values are handled with a
    // flag handshake instead: error_count and first_bad_addr stop changing when the BIST
    // raises done, so capturing them once done has been stable for two sysclk edges
    // reads a settled value, with no synchroniser needed on the data itself.
    wire [N_CH-1:0]        calib_sync, done_sync, pass_sync, busy_sync, ecc_sync;
    reg  [32*N_CH-1:0]     errors_cap;
    reg  [ADDR_W*N_CH-1:0] first_bad_cap;

    genvar s_i;
    generate
        for (s_i = 0; s_i < N_CH; s_i = s_i + 1) begin : gen_sync
            (* ASYNC_REG = "TRUE" *) reg [1:0] calib_q, done_q, pass_q, busy_q, ecc_q;
            always @(posedge sysclk) begin
                calib_q <= {calib_q[0], calib_complete[s_i]};
                done_q  <= {done_q [0], bist_done     [s_i]};
                pass_q  <= {pass_q [0], bist_pass     [s_i]};
                busy_q  <= {busy_q [0], bist_busy     [s_i]};
                ecc_q   <= {ecc_q  [0], ecc_interrupt [s_i]};
            end
            assign calib_sync[s_i] = calib_q[1];
            assign done_sync [s_i] = done_q [1];
            assign pass_sync [s_i] = pass_q [1];
            assign busy_sync [s_i] = busy_q [1];
            assign ecc_sync  [s_i] = ecc_q  [1];

            always @(posedge sysclk) begin
                if (done_q[1]) begin
                    errors_cap   [32*s_i     +: 32]     <= bist_errors   [32*s_i     +: 32];
                    first_bad_cap[ADDR_W*s_i +: ADDR_W] <= bist_first_bad[ADDR_W*s_i +: ADDR_W];
                end
            end
        end
    endgenerate

    // Both nibbles come from the synchronised copies, so the LEDs and the VIO can
    // never disagree about what a channel is doing.
    assign user_led = {pass_sync, calib_sync};

    vio_ddr4 u_vio (
        .clk        (sysclk),
        .probe_in0  (calib_sync),
        .probe_in1  (done_sync),
        .probe_in2  (pass_sync),
        .probe_in3  (busy_sync),
        .probe_in4  (errors_cap[ 32*0 +: 32]),
        .probe_in5  (errors_cap[ 32*1 +: 32]),
        .probe_in6  (errors_cap[ 32*2 +: 32]),
        .probe_in7  (errors_cap[ 32*3 +: 32]),
        .probe_in8  (first_bad_cap[ADDR_W*0 +: ADDR_W]),
        .probe_in9  (first_bad_cap[ADDR_W*1 +: ADDR_W]),
        .probe_in10 (first_bad_cap[ADDR_W*2 +: ADDR_W]),
        .probe_in11 (first_bad_cap[ADDR_W*3 +: ADDR_W]),
        .probe_in12 (ecc_sync),
        .probe_out0 (vio_start)
    );

endmodule

`default_nettype wire
