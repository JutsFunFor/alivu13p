`timescale 1ns/1ps
module tb_ecc_init;
    reg clk=0, resetn=0, calibrated=0;
    always #5 clk=~clk;
    wire ready, failed, awvalid, wvalid, bready;
    wire [31:0] awaddr,wdata;
    reg awready=0,wready=0,bvalid=0;
    reg [1:0] bresp=0;
    ecc_init dut(.*);
    task reset;
        @(negedge clk); resetn=0; calibrated=0;
        awready=0;wready=0;bvalid=0;bresp=0;
        repeat(3) @(negedge clk);
        resetn=1;
        repeat(3) @(negedge clk);
        if (awvalid || wvalid || ready || failed) $fatal(1,"activity before calibration");
        calibrated=1;
    endtask
    task transfer(input bit data_first,input [31:0] address,input [31:0] data,input [1:0] response);
        wait(awvalid && wvalid);
        @(negedge clk);
        if(awaddr!==address || wdata!==data) $fatal(1,"incorrect ECC register write");
        if(data_first) wready=1; else awready=1;
        @(negedge clk);awready=0;wready=0;
        repeat(5) begin
            @(negedge clk);
            if(data_first && (!awvalid || wvalid)) $fatal(1,"W-before-AW handshake lost");
            if(!data_first && (!wvalid || awvalid)) $fatal(1,"AW-before-W handshake lost");
            if(ready || failed || bready) $fatal(1,"premature completion");
            if(awaddr!==address || wdata!==data) $fatal(1,"payload changed while stalled");
        end
        if(data_first) awready=1; else wready=1;
        @(negedge clk);awready=0;wready=0;
        wait(bready);
        repeat(3) @(negedge clk);
        bvalid=1;bresp=response;
        @(negedge clk);bvalid=0;
    endtask
    initial begin
        reset();
        transfer(1,8,1,0);
        transfer(0,4,3,0);
        if(!ready || failed) $fatal(1,"success not reported");
        repeat(10) @(negedge clk);
        if(awvalid || wvalid || !ready) $fatal(1,"success not sticky");
        reset();
        transfer(0,8,1,2);
        if(ready || !failed) $fatal(1,"first write error not detected");
        reset();
        transfer(1,8,1,0);
        transfer(1,4,3,2);
        if(ready || !failed) $fatal(1,"second write error not detected");
        $display("PASS: independent AW/W stalls, delayed responses, reset, both BRESP failures");
        $finish;
    end
    initial begin #10000; $fatal(1,"timeout"); end
endmodule
