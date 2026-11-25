module dense_engine #(parameter integer LANES=4)(
    input wire clk, rst, start,
    input wire [2:0] layer_count,
    output reg [1:0] layer,
    input wire [8:0] in_dim, out_dim,
    input wire [5:0] stride,
    input wire [10:0] weight_base,
    input wire [9:0] bias_base,
    input wire [30:0] multiplier,
    input wire [4:0] shift,
    output wire weight_rd,
    output wire [10:0] weight_addr,
    input wire [63:0] weight_data,
    output wire bias_rd,
    output wire [9:0] bias_addr,
    input wire [31:0] bias_data,
    input wire input_wr,
    input wire [7:0] input_addr, input_data,
    input wire result_rd,
    input wire [7:0] result_addr,
    output wire [31:0] result_data,
    output reg busy, done,
    output reg [31:0] cycles, issues, word_reads
);
    localparam [3:0] IDLE=0, NEURON=1, FETCH=2, ISSUE=3, DRAIN=4,
                     BIAS=5, SCALE=6, COMBINE=7, ROUND=8, STORE=9;
    reg [3:0] state;
    reg bank;
    reg [8:0] neuron, index;
    reg [10:0] row_addr;
    reg signed [31:0] acc, biased;
    reg [31:0] product_ll, product_lh, product_hl, product_hh;
    reg [63:0] scaled;
    reg [7:0] quant;
    wire final_layer = {1'b0,layer}+3'd1 == layer_count;
    wire [8:0] next_index = index + 9'(LANES);
    wire final_group = next_index >= in_dim;
    wire prefetch = state == ISSUE && !final_group && next_index[2:0] == 0;
    wire [8:0] read_index = prefetch ? next_index : index;
    wire hidden_write = state == STORE && !final_layer;
    wire [7:0] input_mask = 8'b1 << input_addr[2:0];
    wire [7:0] hidden_mask = 8'b1 << neuron[2:0];
    wire [63:0] a_data, b_data;
    wire [63:0] activations = bank ? b_data : a_data;
    assign weight_rd = state == FETCH || prefetch;
    assign weight_addr = row_addr + {5'b0,read_index[8:3]};
    assign bias_rd = state == NEURON;
    assign bias_addr = bias_base + {1'b0,neuron};
    packed_ram a_ram(clk, weight_rd && !bank, read_index[7:3], a_data,
        input_wr ? input_addr[7:3] : neuron[7:3],
        input_wr ? input_mask : (hidden_write && bank ? hidden_mask : 8'b0),
        input_wr ? {8{input_data}} : {8{quant}});
    packed_ram b_ram(clk, weight_rd && bank, read_index[7:3], b_data,
        neuron[7:3], hidden_write && !bank ? hidden_mask : 8'b0, {8{quant}});
    packed_ram #(.AW(8), .BYTES(4)) logits(clk, result_rd, result_addr,
        result_data, neuron[7:0], state == STORE && final_layer ? 4'hf : 4'b0, biased);

    wire [LANES-1:0] mask;
    genvar i;
    generate for (i=0; i<LANES; i=i+1) begin : tail
        assign mask[i] = index + i < in_dim;
    end endgenerate
    wire group_valid, group_last;
    wire signed [18:0] sum;
    dot_pipeline #(LANES) dot(clk, rst, state==ISSUE, final_group,
        activations[{index[2:0],3'b0}+:LANES*8],
        weight_data[{index[2:0],3'b0}+:LANES*8],
        mask, group_valid, group_last, sum);
    wire [30:0] relu = biased[31] ? 31'd0 : biased[30:0];
    wire [32:0] cross_terms = {1'b0,product_lh} + {1'b0,product_hl};
    wire [63:0] rounding = shift == 0 ? 64'd0 : (64'd1 << (shift-1'b1));
    wire [63:0] rounded = (scaled + rounding) >> shift;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            layer <= 0;
            bank <= 0;
            neuron <= 0;
            index <= 0;
            row_addr <= 0;
            acc <= 0;
            biased <= 0;
            product_ll <= 0;
            product_lh <= 0;
            product_hl <= 0;
            product_hh <= 0;
            scaled <= 0;
            quant <= 0;
            busy <= 0;
            done <= 0;
            cycles <= 0;
            issues <= 0;
            word_reads <= 0;
        end else begin
            done <= 0;
            if (busy) cycles <= cycles + 1;
            if (weight_rd) word_reads <= word_reads + 1;
            if (group_valid) acc <= acc + {{13{sum[18]}},sum};
            case (state)
                IDLE: if (start) begin
                    busy <= 1;
                    cycles <= 0;
                    issues <= 0;
                    word_reads <= 0;
                    layer <= 0;
                    bank <= 0;
                    neuron <= 0;
                    state <= NEURON;
                end
                NEURON: begin
                    acc <= 0;
                    index <= 0;
                    if (neuron == 0) row_addr <= weight_base;
                    state <= FETCH;
                end
                FETCH: state <= ISSUE;
                ISSUE: begin
                    issues <= issues + 1;
                    if (final_group) state <= DRAIN;
                    else index <= next_index;
                end
                DRAIN: if (group_valid && group_last) state <= BIAS;
                BIAS: begin
                    biased <= acc + $signed(bias_data);
                    state <= final_layer ? STORE : SCALE;
                end
                SCALE: begin
                    product_ll <= relu[15:0] * multiplier[15:0];
                    product_lh <= relu[15:0] * multiplier[30:16];
                    product_hl <= relu[30:16] * multiplier[15:0];
                    product_hh <= relu[30:16] * multiplier[30:16];
                    state <= COMBINE;
                end
                COMBINE: begin
                    scaled <= {product_hh,product_ll} + {15'd0,cross_terms,16'd0};
                    state <= ROUND;
                end
                ROUND: begin
                    quant <= rounded > 127 ? 8'd127 : rounded[7:0];
                    state <= STORE;
                end
                STORE: begin
                    if (neuron + 9'd1 < out_dim) begin
                        neuron <= neuron + 1'b1;
                        row_addr <= row_addr + {5'b0,stride};
                        state <= NEURON;
                    end else if (final_layer) begin
                        busy <= 0;
                        done <= 1;
                        state <= IDLE;
                    end else begin
                        layer <= layer + 1'b1;
                        neuron <= 0;
                        bank <= !bank;
                        state <= NEURON;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
