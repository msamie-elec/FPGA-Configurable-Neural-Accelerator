`timescale 1ns/1ps
// Deterministic extended regression, independent arithmetic scoreboard.
module tb_npu_random;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, start = 0, weight_we = 0;
    reg [31:0] features = 0;
    reg [2:0] weight_addr = 0;
    reg signed [7:0] weight_data = 0;
    wire busy, valid, predicted_class;
    wire signed [31:0] score0, score1;
    integer weights [0:7];
    integer i, j, k, a, b, cases = 0, cycles;
    reg [31:0] stimulus;
    reg signed [7:0] feature_byte;

    npu_core dut (
        .clk(clk), .rst(rst), .start(start), .features(features),
        .weight_we(weight_we), .weight_addr(weight_addr),
        .weight_data(weight_data), .busy(busy), .valid(valid),
        .predicted_class(predicted_class), .score0(score0), .score1(score1)
    );

    task load_weight;
        input integer addr, value;
        begin
            @(negedge clk);
            weight_addr = addr;
            weight_data = value;
            weight_we = 1;
            @(negedge clk);
            weight_we = 0;
            weights[addr] = value;
        end
    endtask

    task check_inference;
        input [31:0] sample;
        begin
            a = 0; b = 0;
            for (k = 0; k < 4; k = k + 1) begin
                feature_byte = $signed(sample[k*8 +: 8]);
                a = a + feature_byte * weights[k];
                b = b + feature_byte * weights[k+4];
            end
            @(negedge clk);
            features = sample;
            start = 1;
            @(negedge clk);
            start = 0;
            // Inputs are latched at start; later host changes must not affect output.
            features = ~sample;
            if (busy !== 1) $fatal(1, "busy not asserted after start");
            cycles = 0;
            while (valid !== 1 && cycles < 20) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (valid !== 1) $fatal(1, "inference timeout sample=%h", sample);
            if (score0 !== a || score1 !== b || predicted_class !== (b > a))
                $fatal(1, "score mismatch sample=%h got=%0d,%0d,%0d expected=%0d,%0d,%0d",
                    sample, score0, score1, predicted_class, a, b, (b>a));
            if (busy !== 0) $fatal(1, "busy still high at valid");
            @(negedge clk);
            if (valid !== 0) $fatal(1, "valid must be one cycle pulse");
            cases = cases + 1;
        end
    endtask

    initial begin
        weights[0] = 2; weights[1] = -1; weights[2] = 1; weights[3] = 0;
        weights[4] = -1; weights[5] = 2; weights[6] = 0; weights[7] = 1;
        repeat (3) @(negedge clk);
        rst = 0;
        check_inference(32'h00000000); // tie
        check_inference(32'h7f80ff01); // signed extremes
        check_inference(32'h80808080);
        check_inference(32'h7f7f7f7f);
        // Runtime weight loading, including both signed INT8 extrema.
        for (i = 0; i < 8; i = i + 1)
            load_weight(i, (i[0] ? -128 : 127));
        check_inference(32'h7f80ff01);
        for (j = 0; j < 128; j = j + 1) begin
            // Fixed deterministic stimulus, no external RNG dependence.
            stimulus = (32'h9e3779b9 * (j + 1)) ^ (32'h5a17b23d >> (j % 15));
            check_inference(stimulus);
        end
        $display("EXTENDED REGRESSION PASS: %0d scored inferences", cases);
        $finish;
    end
endmodule
