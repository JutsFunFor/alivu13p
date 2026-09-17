// Measure the frequency of one probed clock against a known reference.
//
// A free-running counter in the probed domain is sampled at a fixed cadence generated in
// the reference domain. The difference between consecutive samples, divided by the gate
// time, is the probed frequency.
//
// The point of this module is to answer "is anything connected to this pin at all?" on a
// board with no documentation. A pin with no oscillator behind it produces a BUFG_GT
// output that never toggles, so `count_o` stays put and `alive_o` reads low -- which is a
// definite answer, not a timeout.
//
// Clock-domain crossing: `counter` is free-running in `probe_clk_i`, which may be absent
// entirely, so nothing in the reference domain may wait on it. The captured value is
// passed through a two-flop synchroniser. A multi-bit counter crossed this way can be
// sampled mid-increment and yield a torn value, so the counter is Gray-coded before
// crossing: a Gray code changes one bit per increment, so a torn sample is always either
// the old or the new value, never a third.

`default_nettype none

module freq_counter #(
    // Gate length in reference-clock cycles. The measured count is
    //   f_probe = count_delta * f_ref / GATE_CYCLES
    parameter integer GATE_CYCLES = 100_000_000,  // 1 s at 100 MHz
    parameter integer COUNT_W     = 32
) (
    input  wire                 ref_clk_i,    // reference / readout domain
    input  wire                 ref_rst_i,    // active high, synchronous to ref_clk_i

    input  wire                 probe_clk_i,  // may be permanently static

    output reg  [COUNT_W-1:0]   count_o,      // cycles counted during the last gate
    output reg                  valid_o,      // a full gate has completed at least once
    output wire                 alive_o       // the probed clock toggled during that gate
);

    // ---------------------------------------------------------------- probe domain
    reg [COUNT_W-1:0] counter = {COUNT_W{1'b0}};
    reg [COUNT_W-1:0] counter_gray = {COUNT_W{1'b0}};

    always @(posedge probe_clk_i) begin
        counter      <= counter + 1'b1;
        // Gray-code on the way out so the crossing below cannot tear into a bogus value.
        counter_gray <= (counter + 1'b1) ^ ((counter + 1'b1) >> 1);
    end

    // ------------------------------------------------------------ reference domain
    (* ASYNC_REG = "TRUE" *) reg [COUNT_W-1:0] gray_meta = {COUNT_W{1'b0}};
    (* ASYNC_REG = "TRUE" *) reg [COUNT_W-1:0] gray_sync = {COUNT_W{1'b0}};

    always @(posedge ref_clk_i) begin
        gray_meta <= counter_gray;
        gray_sync <= gray_meta;
    end

    // Gray -> binary: each bit is the XOR of all Gray bits at or above it.
    integer i;
    reg [COUNT_W-1:0] binary;
    always @* begin
        binary[COUNT_W-1] = gray_sync[COUNT_W-1];
        for (i = COUNT_W-2; i >= 0; i = i - 1)
            binary[i] = binary[i+1] ^ gray_sync[i];
    end

    localparam integer GATE_W = $clog2(GATE_CYCLES + 1);
    reg [GATE_W-1:0]  gate_cnt = {GATE_W{1'b0}};
    reg [COUNT_W-1:0] last_snapshot = {COUNT_W{1'b0}};

    always @(posedge ref_clk_i) begin
        if (ref_rst_i) begin
            gate_cnt      <= {GATE_W{1'b0}};
            last_snapshot <= {COUNT_W{1'b0}};
            count_o       <= {COUNT_W{1'b0}};
            valid_o       <= 1'b0;
        end else if (gate_cnt == GATE_CYCLES - 1) begin
            gate_cnt      <= {GATE_W{1'b0}};
            // Unsigned subtraction, so a counter wrap is handled without special casing.
            count_o       <= binary - last_snapshot;
            last_snapshot <= binary;
            valid_o       <= 1'b1;
        end else begin
            gate_cnt <= gate_cnt + 1'b1;
        end
    end

    // A handful of counts would be noise on a floating pin; a real clock produces
    // millions per gate. Anything above a few thousand is unambiguously a live clock.
    assign alive_o = valid_o && (count_o > 32'd1000);

endmodule

`default_nettype wire
