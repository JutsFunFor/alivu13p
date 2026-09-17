// Reference-clock probe.
//
// The ALIVU13P is undocumented, so which MGTREFCLK pins actually have an oscillator
// behind them is a question about the board, not the silicon. This design instantiates a
// buffer and a frequency counter on twelve candidate reference clocks at once and reports
// all of them through a VIO, so one bitstream answers the question for every candidate.
//
// Index map -- the first eight are the reference clocks a PCIe x16 endpoint at
// PCIE40E4_X0Y1 can reach (it uses four adjacent GTY quads in SLR1, banks 224-227), which
// is the open question this design exists to settle:
//
//   0   bank 224  MGTREFCLK0   AW9  / AW8
//   1   bank 224  MGTREFCLK1   AV11 / AV10
//   2   bank 225  MGTREFCLK0   AT11 / AT10
//   3   bank 225  MGTREFCLK1   AP11 / AP10
//   4   bank 226  MGTREFCLK0   AM11 / AM10
//   5   bank 226  MGTREFCLK1   AK11 / AK10
//   6   bank 227  MGTREFCLK0   AH11 / AH10
//   7   bank 227  MGTREFCLK1   AF11 / AF10
//
// The last four are controls, not unknowns. Two are already known to carry 161.13 MHz and
// two are known dead, so they calibrate the experiment: if the controls do not read as
// expected, the measurement is wrong and the unknowns must not be trusted.
//
//   8   bank 229  MGTREFCLK0   Y11  / Y10    expect ~161.13 MHz  (dn QSFP cage)
//   9   bank 229  MGTREFCLK1   V11  / V10    expect dead
//   10  bank 233  MGTREFCLK0   D11  / D10    expect ~161.13 MHz  (up QSFP cage)
//   11  bank 233  MGTREFCLK1   B11  / B10    expect dead
//
// A PCIe reference clock is 100 MHz, so the live PCIe candidate should read close to
// 100_000_000 while its seven neighbours read zero.

`default_nettype none

module clk_probe_top #(
    parameter integer N_PROBES = 12,
    // Gate length in sysclk cycles. At 100 MHz this is one second, which makes the
    // reported count directly readable as a frequency in Hz.
    parameter integer GATE_CYCLES = 100_000_000
) (
    // 100 MHz board clock, bank 64. Reference for every measurement, and the free-running
    // clock the debug hub needs.
    input  wire                 sysclk_p,
    input  wire                 sysclk_n,

    input  wire [N_PROBES-1:0]  refclk_p,
    input  wire [N_PROBES-1:0]  refclk_n,

    // QSFP module control. Driven to the inactive state so a module is never held in
    // reset -- see docs/board-facts.md. Index 0 is the dn cage, 1 is the up cage.
    output wire [1:0]           qsfp_resetn,
    output wire [1:0]           qsfp_lpmode
);

    // ------------------------------------------------------------------- reference
    wire sysclk_ibuf;
    // DIFF_TERM must stay FALSE: this input is DIFF_SSTL12 in a 1.2 V bank, and
    // DIFF_TERM_ADV is only legal for standards with internal differential termination.
    IBUFGDS #(.DIFF_TERM("FALSE"), .IBUF_LOW_PWR("FALSE")) u_sysclk_ibuf (
        .I  (sysclk_p),
        .IB (sysclk_n),
        .O  (sysclk_ibuf)
    );

    wire sysclk;
    BUFG u_sysclk_bufg (.I(sysclk_ibuf), .O(sysclk));

    // Release reset after the clock has been running a while. Nothing here depends on a
    // precise reset length; it only has to outlast configuration settling.
    reg [7:0] rst_shift = 8'hFF;
    always @(posedge sysclk) rst_shift <= {rst_shift[6:0], 1'b0};
    wire rst = rst_shift[7];

    // ---------------------------------------------------------------------- probes
    wire [31:0] count   [N_PROBES-1:0];
    wire [N_PROBES-1:0] alive;
    wire [N_PROBES-1:0] valid;

    genvar g;
    generate
        for (g = 0; g < N_PROBES; g = g + 1) begin : gen_probe
            wire refclk_gt;    // to a GT, unused here
            wire refclk_odiv2; // to fabric via BUFG_GT
            wire probe_clk;

            IBUFDS_GTE4 #(
                .REFCLK_EN_TX_PATH  (1'b0),
                .REFCLK_HROW_CK_SEL (2'b00),  // ODIV2 follows the input, undivided
                .REFCLK_ICNTL_RX    (2'b00)
            ) u_refclk_ibuf (
                .I     (refclk_p[g]),
                .IB    (refclk_n[g]),
                .CEB   (1'b0),
                .O     (refclk_gt),
                .ODIV2 (refclk_odiv2)
            );

            // A GT reference clock cannot drive fabric logic directly; BUFG_GT is the
            // only legal route. Without this the counter below would be unroutable.
            BUFG_GT u_refclk_bufg (
                .I       (refclk_odiv2),
                .CE      (1'b1),
                .CEMASK  (1'b0),
                .CLR     (1'b0),
                .CLRMASK (1'b0),
                .DIV     (3'd0),
                .O       (probe_clk)
            );

            freq_counter #(
                .GATE_CYCLES (GATE_CYCLES),
                .COUNT_W     (32)
            ) u_counter (
                .ref_clk_i   (sysclk),
                .ref_rst_i   (rst),
                .probe_clk_i (probe_clk),
                .count_o     (count[g]),
                .valid_o     (valid[g]),
                .alive_o     (alive[g])
            );

            // Keep the unused GT output from being trimmed, which would take the buffer
            // with it and leave nothing driving the pin.
            (* DONT_TOUCH = "TRUE" *) wire refclk_gt_keep = refclk_gt;
        end
    endgenerate

    // QSFP modules: ResetL is active low, LPMode active high.
    assign qsfp_resetn = 2'b11;
    assign qsfp_lpmode = 2'b00;

    // ------------------------------------------------------------------- readout
    // One 32-bit probe per candidate plus a summary vector, read in Hardware Manager.
    vio_probe u_vio (
        .clk        (sysclk),
        .probe_in0  (count[0]),  .probe_in1  (count[1]),
        .probe_in2  (count[2]),  .probe_in3  (count[3]),
        .probe_in4  (count[4]),  .probe_in5  (count[5]),
        .probe_in6  (count[6]),  .probe_in7  (count[7]),
        .probe_in8  (count[8]),  .probe_in9  (count[9]),
        .probe_in10 (count[10]), .probe_in11 (count[11]),
        .probe_in12 (alive),
        .probe_in13 (valid)
    );

endmodule

`default_nettype wire
