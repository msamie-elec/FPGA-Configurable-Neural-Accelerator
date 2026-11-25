// v0.1: 4-input x 2-output signed INT8 dense inference engine.
// One multiply per RUN cycle; weights are changed only while idle.
module npu_core (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire [31:0]        features,   // feature 0 at bits [7:0]
    input  wire               weight_we,
    input  wire [2:0]         weight_addr, // 0..3 output 0; 4..7 output 1
    input  wire signed [7:0]  weight_data,
    output reg                busy,
    output reg                valid,
    output reg                predicted_class,
    output reg signed [31:0]  score0,
    output reg signed [31:0]  score1
);
    localparam [1:0] IDLE = 2'd0, RUN = 2'd1, FINISH = 2'd2;
    reg [1:0] state;
    reg [2:0] idx;
    reg signed [31:0] acc;
    reg [31:0] latched_features;
    reg signed [7:0] weight [0:7];
    reg signed [7:0] feature_value;
    reg signed [15:0] product;
    reg signed [31:0] next_sum;
    integer i;

    always @* begin
        feature_value = $signed(latched_features[{idx[1:0], 3'b000} +: 8]);
        product = feature_value * weight[idx];
        next_sum = acc + {{16{product[15]}}, product};
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            idx <= 0;
            acc <= 0;
            latched_features <= 0;
            busy <= 0;
            valid <= 0;
            predicted_class <= 0;
            score0 <= 0;
            score1 <= 0;
            // Deterministic demonstration weights:
            // output 0 = 2*x0 - x1 + x2
            // output 1 = -x0 + 2*x1 + x3
            weight[0] <= 8'sd2;  weight[1] <= -8'sd1;
            weight[2] <= 8'sd1;  weight[3] <= 8'sd0;
            weight[4] <= -8'sd1; weight[5] <= 8'sd2;
            weight[6] <= 8'sd0;  weight[7] <= 8'sd1;
        end else begin
            valid <= 0;
            case (state)
                IDLE: begin
                    busy <= 0;
                    if (weight_we)
                        weight[weight_addr] <= weight_data;
                    if (start && !weight_we) begin
                        latched_features <= features;
                        idx <= 0;
                        acc <= 0;
                        busy <= 1;
                        state <= RUN;
                    end
                end
                RUN: begin
                    if (idx == 3) begin
                        score0 <= next_sum;
                        acc <= 0;
                    end else if (idx == 7) begin
                        score1 <= next_sum;
                        predicted_class <= (next_sum > score0);
                        acc <= 0;
                        state <= FINISH;
                    end else begin
                        acc <= next_sum;
                    end
                    idx <= idx + 1'b1;
                end
                FINISH: begin
                    busy <= 0;
                    valid <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
