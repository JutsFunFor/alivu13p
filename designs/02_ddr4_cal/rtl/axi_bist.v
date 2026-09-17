// Minimal AXI4 memory test: write a pattern across a region, read it back, compare.
//
// This is a functional test, not a bandwidth benchmark. It issues single-beat bursts,
// which keeps the state machine small enough to be obviously correct and still exercises
// the full path -- controller, PHY, board traces and DRAM. A torn address line or a
// mis-calibrated byte lane shows up immediately as a mismatch, which is what this is for.
//
// The pattern is address-derived rather than constant, so a read returning the wrong
// location's data fails rather than passing by coincidence -- the failure mode a constant
// pattern is blind to.

`default_nettype none

module axi_bist #(
    parameter integer ADDR_W   = 32,
    parameter integer DATA_W   = 512,
    parameter integer ID_W     = 1,
    // Number of words to test. Must be a power of two: the low half of the index range
    // runs the dense walk and the high half runs the sparse one.
    parameter integer N_WORDS  = 8192,
    // Byte address increment for the dense walk -- one AXI word, so consecutive words
    // land in consecutive columns of one row.
    parameter integer STRIDE   = DATA_W / 8,
    // Byte address increment for the sparse walk. 1 MB x 4096 words covers the whole
    // 4 GB of a channel, so every address bit gets exercised.
    parameter integer SPARSE_STRIDE = 32'h0010_0000,
    // Where the dense walk starts. Not zero, and that matters: the sparse walk's first
    // word is at address zero, so a dense walk starting there too would have its word
    // overwritten during the write pass and report a mismatch on a perfectly good
    // channel. Offsetting it drops the dense range strictly between the first two sparse
    // points, leaving the two walks disjoint.
    parameter integer DENSE_BASE = 32'h0000_8000
) (
    input  wire                 clk,
    input  wire                 rst,          // active high, synchronous

    input  wire                 start,        // pulse or level; latched when idle
    output reg                  busy,
    output reg                  done,
    output reg                  pass,
    output reg  [31:0]          error_count,
    output reg  [ADDR_W-1:0]    first_bad_addr,

    // AXI4 write address
    output reg  [ID_W-1:0]      m_axi_awid,
    output reg  [ADDR_W-1:0]    m_axi_awaddr,
    output wire [7:0]           m_axi_awlen,
    output wire [2:0]           m_axi_awsize,
    output wire [1:0]           m_axi_awburst,
    output reg                  m_axi_awvalid,
    input  wire                 m_axi_awready,
    // AXI4 write data
    output reg  [DATA_W-1:0]    m_axi_wdata,
    output wire [DATA_W/8-1:0]  m_axi_wstrb,
    output wire                 m_axi_wlast,
    output reg                  m_axi_wvalid,
    input  wire                 m_axi_wready,
    // AXI4 write response
    input  wire [1:0]           m_axi_bresp,
    input  wire                 m_axi_bvalid,
    output wire                 m_axi_bready,
    // AXI4 read address
    output reg  [ID_W-1:0]      m_axi_arid,
    output reg  [ADDR_W-1:0]    m_axi_araddr,
    output wire [7:0]           m_axi_arlen,
    output wire [2:0]           m_axi_arsize,
    output wire [1:0]           m_axi_arburst,
    output reg                  m_axi_arvalid,
    input  wire                 m_axi_arready,
    // AXI4 read data
    input  wire [DATA_W-1:0]    m_axi_rdata,
    input  wire [1:0]           m_axi_rresp,
    input  wire                 m_axi_rlast,
    input  wire                 m_axi_rvalid,
    output wire                 m_axi_rready
);

    // Single-beat INCR bursts of the full data width.
    assign m_axi_awlen   = 8'd0;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_awburst = 2'b01;
    assign m_axi_arburst = 2'b01;
    assign m_axi_wstrb   = {(DATA_W/8){1'b1}};
    assign m_axi_wlast   = 1'b1;
    assign m_axi_bready  = 1'b1;
    assign m_axi_rready  = 1'b1;

    // AxSIZE is log2 of the bytes per beat.
    localparam integer SIZE_ENC = $clog2(DATA_W / 8);
    assign m_axi_awsize = SIZE_ENC[2:0];
    assign m_axi_arsize = SIZE_ENC[2:0];

    // Address-derived pattern. Repeating the index across the word means a swapped byte
    // lane is visible, while mixing in a constant keeps it from being all-zero at index 0.
    function [DATA_W-1:0] pattern;
        input [31:0] index;
        integer k;
        begin
            for (k = 0; k < DATA_W / 32; k = k + 1)
                pattern[k*32 +: 32] = index ^ {16'hA5A5, k[15:0]};
        end
    endfunction

    localparam [2:0] S_IDLE  = 3'd0,
                     S_WADDR = 3'd1,
                     S_WDATA = 3'd2,
                     S_WRESP = 3'd3,
                     S_RADDR = 3'd4,
                     S_RDATA = 3'd5,
                     S_DONE  = 3'd6;

    reg [2:0]  state;
    reg [31:0] index;
    reg        aw_done, w_done;

    // Two walks in one pass, selected by the top bit of the index.
    //
    // A dense walk alone is a weak memory test: it stays inside one row, so a swapped or
    // stuck high address line never changes a bit that the test observes, and every
    // access lands where it was meant to by accident. A sparse walk alone misses the
    // opposite failure -- neighbouring columns interfering -- and never repeats a row.
    // Running both covers each other's blind spot for the cost of one multiplexer.
    localparam integer LOG2N = $clog2(N_WORDS);
    wire                sparse    = index[LOG2N-1];
    wire [31:0]         sub_index = index & ((1 << (LOG2N-1)) - 1);
    wire [ADDR_W-1:0]   addr_of_index =
        sparse ? (sub_index * SPARSE_STRIDE) : (DENSE_BASE + sub_index * STRIDE);

    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            index          <= 32'd0;
            busy           <= 1'b0;
            done           <= 1'b0;
            pass           <= 1'b0;
            error_count    <= 32'd0;
            first_bad_addr <= {ADDR_W{1'b0}};
            m_axi_awvalid  <= 1'b0;
            m_axi_wvalid   <= 1'b0;
            m_axi_arvalid  <= 1'b0;
            m_axi_awid     <= {ID_W{1'b0}};
            m_axi_arid     <= {ID_W{1'b0}};
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state          <= S_WADDR;
                        index          <= 32'd0;
                        busy           <= 1'b1;
                        done           <= 1'b0;
                        pass           <= 1'b0;
                        error_count    <= 32'd0;
                        first_bad_addr <= {ADDR_W{1'b0}};
                    end
                end

                // Address and data channels are independent; drive both and retire each
                // when its handshake completes rather than serialising them.
                S_WADDR: begin
                    m_axi_awaddr  <= addr_of_index;
                    m_axi_awvalid <= 1'b1;
                    m_axi_wdata   <= pattern(index);
                    m_axi_wvalid  <= 1'b1;
                    aw_done       <= 1'b0;
                    w_done        <= 1'b0;
                    state         <= S_WDATA;
                end

                S_WDATA: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        aw_done       <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        w_done        <= 1'b1;
                    end
                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done  || (m_axi_wvalid  && m_axi_wready ))) begin
                        state <= S_WRESP;
                    end
                end

                S_WRESP: begin
                    if (m_axi_bvalid) begin
                        if (m_axi_bresp != 2'b00) begin
                            if (error_count == 32'd0) first_bad_addr <= addr_of_index;
                            error_count <= error_count + 1'b1;
                        end
                        if (index == N_WORDS - 1) begin
                            index <= 32'd0;
                            state <= S_RADDR;
                        end else begin
                            index <= index + 1'b1;
                            state <= S_WADDR;
                        end
                    end
                end

                S_RADDR: begin
                    m_axi_araddr  <= addr_of_index;
                    m_axi_arvalid <= 1'b1;
                    state         <= S_RDATA;
                end

                S_RDATA: begin
                    if (m_axi_arvalid && m_axi_arready) m_axi_arvalid <= 1'b0;
                    if (m_axi_rvalid) begin
                        if (m_axi_rdata != pattern(index) || m_axi_rresp != 2'b00) begin
                            if (error_count == 32'd0) first_bad_addr <= addr_of_index;
                            error_count <= error_count + 1'b1;
                        end
                        if (index == N_WORDS - 1) begin
                            state <= S_DONE;
                        end else begin
                            index <= index + 1'b1;
                            state <= S_RADDR;
                        end
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    pass  <= (error_count == 32'd0);
                    if (!start) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
