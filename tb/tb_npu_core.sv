`timescale 1ns/1ps
module tb_npu_core;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, start = 0, weight_we = 0;
    reg [31:0] features = 0;
    reg [2:0] weight_addr = 0;
    reg signed [7:0] weight_data = 0;
    wire busy, valid, predicted_class;
    wire signed [31:0] score0, score1;
    integer failures = 0;
    integer cycles;

    npu_core dut (
        .clk(clk), .rst(rst), .start(start),
        .features(features), .weight_we(weight_we),
        .weight_addr(weight_addr), .weight_data(weight_data),
        .busy(busy), .valid(valid),
        .predicted_class(predicted_class),
        .score0(score0), .score1(score1)
    );

    task inference;
        input [31:0] data_in;
        input integer expected0, expected1, expected_class;
        begin
            @(negedge clk);
            features = data_in;
            start = 1;
            @(negedge clk);
            start = 0;
            cycles = 0;
            while (!valid && cycles < 30) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (!valid) begin
                $display("FAIL: valid timeout");
                failures = failures + 1;
            end else if (score0 !== expected0 || score1 !== expected1 ||
                         predicted_class !== expected_class) begin
                $display("FAIL: input=%h score0=%0d score1=%0d class=%0d expected %0d %0d %0d",
                    data_in, score0, score1, predicted_class,
                    expected0, expected1, expected_class);
                failures = failures + 1;
            end else
                $display("PASS: %h => scores %0d, %0d class %0d (%0d cycles)",
                    data_in, score0, score1, predicted_class, cycles);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        inference(32'h00000105, 9, -3, 0);
        inference(32'h00000500, -5, 10, 1);
        @(negedge clk);
        weight_addr = 0; weight_data = -8'sd10; weight_we = 1;
        @(negedge clk);
        weight_we = 0;
        inference(32'h00000105, -51, -3, 1);
        if (failures != 0) $fatal(1, "Regression failed: %0d cases", failures);
        $display("ALL TESTS PASS");
        $finish;
    end
endmodule
