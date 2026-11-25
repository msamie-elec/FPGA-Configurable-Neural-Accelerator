// Configurable INT8 MLP inference engine, independent of legacy board demo.
// Maximum 3 layers, maximum 8 neurons per layer; 1, 4 or 8 MAC lanes.
// Weight map: layer*64 + neuron*8 + input. Bias map: layer*8 + neuron.
// All weights/biases must be initialized by host before inference.
module mlp_engine #(parameter integer LANES=4)(
  input wire clk,rst,start,
  input wire [63:0] features,
  input wire [1:0] layer_count,
  input wire [3:0] input_size,layer0_size,layer1_size,layer2_size,
  input wire [3:0] output_shift,
  input wire weight_we,
  input wire [7:0] weight_addr,
  input wire signed [7:0] weight_data,
  input wire bias_we,
  input wire [4:0] bias_addr,
  input wire signed [31:0] bias_data,
  output reg busy,valid,error,
  output reg [2:0] predicted_class,
  output reg [63:0] outputs
);
  localparam [2:0] IDLE=0, ISSUE=1, ACCUM=2, STORE=3, DONE=4;
  reg [2:0] state;
  reg signed [7:0] weights[0:191];
  reg signed [31:0] biases[0:23];
  reg signed [7:0] act_a[0:7],act_b[0:7];
  (* use_dsp = "yes" *) reg signed [15:0] product_reg[0:LANES-1];
  reg signed [7:0] activation[0:LANES-1], lane_weight[0:LANES-1];
  reg [2:0] layer_idx;
  reg [3:0] in_count,out_count,neuron_idx,group_idx;
  reg [1:0] layer_count_q;
  reg [3:0] size0_q,size1_q,size2_q,shift_q;
  reg signed [31:0] accumulator,sum_products,raw_result,scaled;
  reg signed [7:0] quantized,best_value;
  reg [2:0] best_index;
  integer k, widx;
  initial begin
    if (LANES!=1 && LANES!=4 && LANES!=8)
      $error("LANES must be 1/4/8");
  end
  always @* begin
    for (integer p=0;p<LANES;p=p+1) begin
      activation[p]=0;
      lane_weight[p]=0;
      if ((group_idx*LANES+p)<in_count) begin
        if (layer_idx[0]==0)
          activation[p]=act_a[group_idx*LANES+p];
        else
          activation[p]=act_b[group_idx*LANES+p];
        widx=layer_idx*64+neuron_idx*8+(group_idx*LANES+p);
        lane_weight[p]=weights[widx];
      end
    end
    sum_products=accumulator;
    for (integer p=0;p<LANES;p=p+1)
      sum_products=sum_products+{{16{product_reg[p][15]}},product_reg[p]};
    // In STORE the accumulator already includes the final product group.
    raw_result=accumulator+biases[layer_idx*8+neuron_idx];
    scaled=raw_result >>> shift_q;
    if (scaled>127) quantized=127;
    else if (scaled < -128) quantized=-128;
    else quantized=scaled[7:0];
    if (layer_idx!=(layer_count_q-1) && quantized<0) quantized=0;
  end
  always @(posedge clk) begin
    if (rst) begin
      state<=IDLE;busy<=0;valid<=0;error<=0;outputs<=0;
      predicted_class<=0;layer_idx<=0;neuron_idx<=0;group_idx<=0;
      accumulator<=0;best_value<=-128;best_index<=0;
      in_count<=0;out_count<=0;layer_count_q<=0;
      size0_q<=0;size1_q<=0;size2_q<=0;shift_q<=0;
      for (k=0;k<8;k=k+1) begin act_a[k]<=0;act_b[k]<=0;end
      for (k=0;k<LANES;k=k+1) product_reg[k]<=0;
      // Do not reset weights/bias memories: host initializes them.
    end else begin
      valid<=0;
      case(state)
        IDLE: begin
          busy<=0;
          if (weight_we && weight_addr<192) weights[weight_addr]<=weight_data;
          if (bias_we && bias_addr<24) biases[bias_addr]<=bias_data;
          if (start && !weight_we && !bias_we) begin
            if (layer_count<1 || layer_count>3 ||
                input_size<1 || input_size>8 ||
                layer0_size<1 || layer0_size>8 ||
                (layer_count>1 && (layer1_size<1 || layer1_size>8)) ||
                (layer_count>2 && (layer2_size<1 || layer2_size>8))) begin
              error<=1;valid<=1;
            end else begin
              error<=0;busy<=1;
              layer_count_q<=layer_count;
              size0_q<=layer0_size;size1_q<=layer1_size;
              size2_q<=layer2_size;shift_q<=output_shift;
              in_count<=input_size;out_count<=layer0_size;
              layer_idx<=0;neuron_idx<=0;group_idx<=0;
              accumulator<=0;outputs<=0;
              best_value<=-128;best_index<=0;
              for (k=0;k<8;k=k+1)
                act_a[k]<=$signed(features[k*8+:8]);
              state<=ISSUE;
            end
          end
        end
        ISSUE: begin
          for (k=0;k<LANES;k=k+1)
            product_reg[k]<=activation[k]*lane_weight[k];
          state<=ACCUM;
        end
        ACCUM: begin
          accumulator<=sum_products;
          if ((group_idx+1)*LANES>=in_count) state<=STORE;
          else begin group_idx<=group_idx+1'b1;state<=ISSUE;end
        end
        STORE: begin
          if (layer_idx[0]==0) act_b[neuron_idx]<=quantized;
          else act_a[neuron_idx]<=quantized;
          if (layer_idx==(layer_count_q-1)) begin
            outputs[neuron_idx*8+:8]<=quantized;
            if (neuron_idx==0 || quantized>best_value) begin
              best_value<=quantized;best_index<=neuron_idx[2:0];
            end
          end
          accumulator<=0;group_idx<=0;
          if (neuron_idx+1<out_count) begin
            neuron_idx<=neuron_idx+1'b1;state<=ISSUE;
          end else if (layer_idx+1<layer_count_q) begin
            layer_idx<=layer_idx+1'b1;neuron_idx<=0;
            in_count<=out_count;
            out_count<=(layer_idx==0)?size1_q:size2_q;
            state<=ISSUE;
          end else begin
            predicted_class<=(neuron_idx==0 || quantized>best_value)
              ? neuron_idx[2:0]:best_index;
            state<=DONE;
          end
        end
        DONE: begin busy<=0;valid<=1;state<=IDLE;end
        default: state<=IDLE;
      endcase
    end
  end
endmodule
