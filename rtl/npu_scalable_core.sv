// Experimental scalable inference core. Separate from the proven Arty top.
// Up to 32 inputs, three 32-wide hidden layers, eight outputs (104 neurons).
// Four sequential dense layers, eight shared parallel INT8 multiplication lanes.
// One physical multiply bank is reused for every neuron and every layer.
// Weight address: layer*1024 + neuron*32 + input (12 bits).
// Bias address: layer*32 + neuron (7 bits).
// Host must preload every used weight and bias before start.
module npu_scalable_core (
  input wire clk, rst, start,
  input wire [255:0] features,
  input wire [2:0] layer_count,             // 1..4 computational layers
  input wire [5:0] input_size,              // 1..32 features
  input wire [5:0] size0, size1, size2, size3,
  input wire [3:0] shift,                   // same arithmetic shift for each layer
  input wire weight_we,
  input wire [11:0] weight_addr,
  input wire signed [7:0] weight_data,
  input wire bias_we,
  input wire [6:0] bias_addr,
  input wire signed [31:0] bias_data,
  output reg busy, valid, error,
  output reg [2:0] predicted_class,
  output reg [63:0] outputs
);
  localparam [3:0]
    IDLE=0, READ_WEIGHT=1, MULTIPLY=2, REDUCE1=3, REDUCE2=4,
    ACCUMULATE=5, STORE=6, DONE=7;
  reg [3:0] state;
  reg [2:0] layer_idx, layers_q;
  reg [5:0] width0_q, width1_q, width2_q, width3_q;
  reg [5:0] in_count, out_count;
  reg [5:0] neuron_idx;
  reg [1:0] group_idx;                  // 32 input slots / 8 lanes = 4 groups
  reg [3:0] shift_q;
  reg signed [7:0] activation_a[0:31];
  reg signed [7:0] activation_b[0:31];
  reg signed [31:0] biases[0:127];
  wire signed [7:0] read_weights[0:7];
  wire [8:0] weight_read_row = {layer_idx[1:0],7'b0}
      + {neuron_idx[4:0],2'b0} + {7'b0,group_idx};
  reg signed [15:0] products[0:7];
  reg signed [17:0] sums_a[0:3];
  reg signed [19:0] sums_b[0:1];
  reg signed [31:0] acc;
  reg signed [31:0] weighted_sum;
  reg signed [31:0] shifted_sum;
  reg signed [7:0] clipped;
  reg signed [7:0] peak_value;
  reg [2:0] peak_index;
  reg [5:0] requested_width;
  integer i;

  genvar lane;
  generate for(lane=0;lane<8;lane=lane+1) begin: bank
    npu_weight_bank bank_inst(
      .clk(clk),
      .read_addr(weight_read_row),
      .read_data(read_weights[lane]),
      .write_enable(weight_we && !busy && (weight_addr[2:0]==lane)),
      .write_addr(weight_addr[11:3]),
      .write_data(weight_data)
    );
  end endgenerate

  // This register bank can be changed in IDLE only.
  always @(posedge clk) begin
    if (bias_we && !busy) biases[bias_addr] <= bias_data;
  end

  always @* begin
    case (layer_count-1'b1)
      0: requested_width=size0;
      1: requested_width=size1;
      2: requested_width=size2;
      default: requested_width=size3;
    endcase
    weighted_sum = acc + biases[{layer_idx[1:0],5'b0}+neuron_idx];
    shifted_sum = weighted_sum >>> shift_q;
    if (shifted_sum>127) clipped=8'sd127;
    else if (shifted_sum< -128) clipped=-8'sd128;
    else clipped=shifted_sum[7:0];
    if (layer_idx != layers_q-1 && clipped<0) clipped=0;
  end

  always @(posedge clk) begin
    if(rst) begin
      state<=IDLE; busy<=0;valid<=0;error<=0;
      outputs<=0;predicted_class<=0;
      layer_idx<=0; layers_q<=0;neuron_idx<=0;group_idx<=0;
      in_count<=0;out_count<=0;acc<=0;shift_q<=0;
      width0_q<=0;width1_q<=0;width2_q<=0;width3_q<=0;
      peak_value<=-128;peak_index<=0;
      for(i=0;i<32;i=i+1) begin
        activation_a[i]<=0;activation_b[i]<=0;
      end
      for(i=0;i<8;i=i+1) products[i]<=0;
      for(i=0;i<4;i=i+1) sums_a[i]<=0;
      for(i=0;i<2;i=i+1) sums_b[i]<=0;
      // Weight and bias memories intentionally not reset.
    end else begin
      valid<=0;
      case(state)
        IDLE: begin
          busy<=0;
          if(start && !weight_we && !bias_we) begin
            if(layer_count<1 || layer_count>4 || input_size<1 || input_size>32 ||
               size0<1 || size0>32 ||
               (layer_count>1 && (size1<1 || size1>32)) ||
               (layer_count>2 && (size2<1 || size2>32)) ||
               (layer_count>3 && (size3<1 || size3>32)) ||
               requested_width>8) begin
              error<=1;valid<=1;
            end else begin
              error<=0;busy<=1;
              layers_q<=layer_count;
              width0_q<=size0;width1_q<=size1;
              width2_q<=size2;width3_q<=size3;
              shift_q<=shift;
              in_count<=input_size;out_count<=size0;
              layer_idx<=0;neuron_idx<=0;group_idx<=0;acc<=0;
              outputs<=0;peak_value<=-128;peak_index<=0;
              for(i=0;i<32;i=i+1)
                activation_a[i]<=$signed(features[i*8+:8]);
              state<=READ_WEIGHT;
            end
          end
        end
        READ_WEIGHT: begin
          // Synchronous weight-bank reads occur at this edge.
          state<=MULTIPLY;
        end
        MULTIPLY: begin
          for(i=0;i<8;i=i+1) begin
            if((group_idx*8+i)<in_count) begin
              if(layer_idx[0]==0)
                products[i] <= activation_a[group_idx*8+i] * read_weights[i];
              else
                products[i] <= activation_b[group_idx*8+i] * read_weights[i];
            end else products[i]<=0;
          end
          state<=REDUCE1;
        end
        REDUCE1: begin
          for(i=0;i<4;i=i+1)
            sums_a[i] <= {{2{products[2*i][15]}},products[2*i]}
                         + {{2{products[2*i+1][15]}},products[2*i+1]};
          state<=REDUCE2;
        end
        REDUCE2: begin
          sums_b[0] <= {{2{sums_a[0][17]}},sums_a[0]}
                      + {{2{sums_a[1][17]}},sums_a[1]};
          sums_b[1] <= {{2{sums_a[2][17]}},sums_a[2]}
                      + {{2{sums_a[3][17]}},sums_a[3]};
          state<=ACCUMULATE;
        end
        ACCUMULATE: begin
          // Bias added only in STORE; accumulated group sums do not include it.
          acc <= acc + {{12{sums_b[0][19]}},sums_b[0]}
                     + {{12{sums_b[1][19]}},sums_b[1]};
          if(group_idx==3 || ({group_idx,3'b000}+8)>=in_count)
            state<=STORE;
          else begin group_idx<=group_idx+1'b1;state<=READ_WEIGHT;end
        end
        STORE: begin
          // acc includes all product groups; add the bias exactly once.
          if(layer_idx[0]==0) activation_b[neuron_idx]<=clipped;
          else activation_a[neuron_idx]<=clipped;
          if(layer_idx==layers_q-1) begin
            outputs[neuron_idx*8+:8]<=clipped;
            if(neuron_idx==0 || clipped>peak_value) begin
              peak_value<=clipped;
              peak_index<=neuron_idx[2:0];
            end
          end
          acc<=0;group_idx<=0;
          if(neuron_idx+1<out_count) begin
            neuron_idx<=neuron_idx+1'b1;
            state<=READ_WEIGHT;
          end else if(layer_idx+1<layers_q) begin
            layer_idx<=layer_idx+1'b1;
            neuron_idx<=0;
            in_count<=out_count;
            case(layer_idx)
              0:out_count<=width1_q;
              1:out_count<=width2_q;
              default:out_count<=width3_q;
            endcase
            state<=READ_WEIGHT;
          end else begin
            predicted_class<=(neuron_idx==0 || clipped>peak_value)
                ? neuron_idx[2:0] : peak_index;
            state<=DONE;
          end
        end
        DONE: begin busy<=0;valid<=1;state<=IDLE;end
        default:state<=IDLE;
      endcase
    end
  end
endmodule
