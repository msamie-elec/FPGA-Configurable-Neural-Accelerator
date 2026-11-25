`timescale 1ns/1ps
module tb_mlp_engine;
  parameter integer LANES=4;
  reg clk=0;
  always #5 clk=~clk;
  reg rst=1,start=0,weight_we=0,bias_we=0;
  reg [63:0] features=0;
  reg [1:0] layer_count=3;
  reg [3:0] input_size=4,layer0_size=8,layer1_size=4,layer2_size=2;
  reg [3:0] output_shift=0;
  reg [7:0] weight_addr=0;
  reg signed [7:0] weight_data=0;
  reg [4:0] bias_addr=0;
  reg signed [31:0] bias_data=0;
  wire busy,valid,error;
  wire [2:0] predicted_class;
  wire [63:0] outputs;
  integer i,cycles;
  mlp_engine #(.LANES(LANES)) dut(
    .clk(clk),.rst(rst),.start(start),.features(features),
    .layer_count(layer_count),.input_size(input_size),
    .layer0_size(layer0_size),.layer1_size(layer1_size),
    .layer2_size(layer2_size),.output_shift(output_shift),
    .weight_we(weight_we),.weight_addr(weight_addr),.weight_data(weight_data),
    .bias_we(bias_we),.bias_addr(bias_addr),.bias_data(bias_data),
    .busy(busy),.valid(valid),.error(error),
    .predicted_class(predicted_class),.outputs(outputs)
  );
  task set_weight;
    input integer addr,value;
    begin
      @(negedge clk);weight_we=1;weight_addr=addr;weight_data=value;
      @(negedge clk);weight_we=0;
    end
  endtask
  task set_bias;
    input integer addr,value;
    begin
      @(negedge clk);bias_we=1;bias_addr=addr;bias_data=value;
      @(negedge clk);bias_we=0;
    end
  endtask
  task run_check;
    input [63:0] sample;
    input integer expected0,expected1,winner;
    begin
      @(negedge clk);features=sample;start=1;
      @(negedge clk);start=0;features=0;
      cycles=0;
      while (valid!==1'b1 && cycles<600) begin
        @(negedge clk);cycles=cycles+1;
      end
      if (!valid || error || $signed(outputs[7:0])!==expected0 ||
          $signed(outputs[15:8])!==expected1 ||
          predicted_class!==winner)
        $fatal(1,"LANES=%0d expected %0d,%0d class=%0d got %0d,%0d class=%0d err=%0d after %0d",
          LANES,expected0,expected1,winner,
          $signed(outputs[7:0]),$signed(outputs[15:8]),predicted_class,error,cycles);
      $display("PASS lanes=%0d outputs=%0d,%0d winner=%0d cycles=%0d",
        LANES,expected0,expected1,winner,cycles);
      @(negedge clk);
      if (valid!==0) $fatal(1,"valid must pulse one cycle");
    end
  endtask
  initial begin
    repeat(3) @(negedge clk);
    rst=0;
    for(i=0;i<192;i=i+1) set_weight(i,0);
    for(i=0;i<24;i=i+1) set_bias(i,0);
    // Three-layer MLP 4->8->4->2. Hidden layers are ReLU identities.
    for(i=0;i<4;i=i+1) begin
      set_weight(i*8+i,1);
      set_weight(64+i*8+i,1);
    end
    set_weight(128,1);
    set_weight(137,1);
    run_check(64'h0000000001020305,5,3,0);
    run_check(64'h0000000002010701,1,7,1);
    run_check(64'h0000000000000000,0,0,0);
    // Runtime topology reconfiguration: 4->2, without resynthesis.
    layer_count=1;layer0_size=2;
    for(i=0;i<64;i=i+1) set_weight(i,0);
    set_weight(0,2);set_weight(9,3);
    run_check(64'h0000000000000402,4,12,1);
    @(negedge clk);layer_count=0;start=1;
    @(negedge clk);start=0;
    if (!valid || !error || busy) $fatal(1,"invalid topology not rejected");
    $display("MLP ENGINE PASS lanes=%0d",LANES);
    $finish;
  end
endmodule
