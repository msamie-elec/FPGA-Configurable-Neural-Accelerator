// Arty A7 35T demonstration interface; this is the only FPGA top.
module arty_a7_top (
    input  wire       clk100,
    input  wire [3:0] sw,
    input  wire [1:0] btn,
    output wire [3:0] led
);
    reg [1:0] reset_sync = 2'b11;
    always @(posedge clk100)
        reset_sync <= {reset_sync[0], btn[1]};
    wire rst = reset_sync[1];

    reg [1:0] btn_sync = 0;
    reg btn_previous = 0;
    always @(posedge clk100) begin
        btn_sync <= {btn_sync[0], btn[0]};
        btn_previous <= btn_sync[1];
    end
    wire start = btn_sync[1] && !btn_previous;

    // Four independent demo sensor channels, each 0 or +8.
    wire [31:0] features = {
        (sw[3] ? 8'd8 : 8'd0),
        (sw[2] ? 8'd8 : 8'd0),
        (sw[1] ? 8'd8 : 8'd0),
        (sw[0] ? 8'd8 : 8'd0)
    };
    wire busy, valid, predicted_class;
    wire signed [31:0] score0, score1;
    reg result_seen = 0;

    npu_core core (
        .clk(clk100), .rst(rst), .start(start),
        .features(features),
        .weight_we(1'b0), .weight_addr(3'b0),
        .weight_data(8'sd0),
        .busy(busy), .valid(valid),
        .predicted_class(predicted_class),
        .score0(score0), .score1(score1)
    );
    always @(posedge clk100) begin
        if (rst)
            result_seen <= 0;
        else if (valid)
            result_seen <= 1;
    end
    assign led[0] = result_seen && !predicted_class;
    assign led[1] = result_seen && predicted_class;
    assign led[2] = result_seen;
    assign led[3] = busy;
endmodule
