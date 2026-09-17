// Enable ECC checking and both MIG ECC interrupt classes before host DMA.
// Independent AXI-Lite AW/W handshakes; BRESP errors prevent ready assertion.
`timescale 1ns/1ps
`default_nettype none
module ecc_init (
    input wire clk,
    input wire resetn,
    input wire calibrated,
    output reg ready,
    output reg failed,
    output wire [31:0] awaddr,
    output wire awvalid,
    input wire awready,
    output wire [31:0] wdata,
    output wire wvalid,
    input wire wready,
    input wire [1:0] bresp,
    input wire bvalid,
    output wire bready
);
    localparam IDLE=0, SEND=1, RESP=2, DONE=3;
    reg [1:0] state;
    reg second, aw_done, w_done;
    assign awaddr = second ? 32'h04 : 32'h08;
    assign wdata = second ? 32'h03 : 32'h01;
    assign awvalid = state == SEND && !aw_done;
    assign wvalid = state == SEND && !w_done;
    assign bready = state == RESP;
    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            second <= 0;
            aw_done <= 0;
            w_done <= 0;
            ready <= 0;
            failed <= 0;
        end else case (state)
            IDLE: if (calibrated) state <= SEND;
            SEND: begin
                if (awvalid && awready) aw_done <= 1;
                if (wvalid && wready) w_done <= 1;
                if ((aw_done || awready) && (w_done || wready)) state <= RESP;
            end
            RESP: if (bvalid) begin
                if (bresp != 0) begin
                    failed <= 1;
                    state <= DONE;
                end else if (second) begin
                    ready <= 1;
                    state <= DONE;
                end else begin
                    second <= 1;
                    aw_done <= 0;
                    w_done <= 0;
                    state <= SEND;
                end
            end
            DONE: state <= DONE;
            default: state <= IDLE;
        endcase
    end
endmodule
`default_nettype wire
