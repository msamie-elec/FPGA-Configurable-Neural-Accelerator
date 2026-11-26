`timescale 1ns/1ps
// Independent corner cases for the public, non-UART synchronous IP contract.
// Untrained 1-input / 2-output model; deterministic expected arithmetic.
module tb_npu_corner_cases;
  reg clk=0;
  always #5 clk=~clk;
  reg rst=1,start=0,weight_we=0,bias_we=0;
  reg [255:0] features=0;
  reg [2:0] layer_count=1;
  reg [5:0] input_size=1,size0=2,size1=1,size2=1,size3=1;
  reg [3:0] shift=0;
  reg [11:0] weight_addr=0;
  reg signed [7:0] weight_data=0;
  reg [6:0] bias_addr=0;
  reg signed [31:0] bias_data=0;
  wire busy,valid,error;
  wire [2:0] predicted_class;
  wire [63:0] outputs;
  npu_accelerator_ip dut(.clk(clk),.rst(rst),.start(start),.features(features),
    .layer_count(layer_count),.input_size(input_size),.size0(size0),
    .size1(size1),.size2(size2),.size3(size3),.shift(shift),
    .weight_we(weight_we),.weight_addr(weight_addr),.weight_data(weight_data),
    .bias_we(bias_we),.bias_addr(bias_addr),.bias_data(bias_data),
    .busy(busy),.valid(valid),.error(error),
    .predicted_class(predicted_class),.outputs(outputs));

  task write_weight;
    input [11:0] a; input signed [7:0] v;
    begin @(negedge clk);weight_addr=a;weight_data=v;weight_we=1;
      @(negedge clk);weight_we=0;end
  endtask
  task write_bias;
    input [6:0] a;input signed [31:0] v;
    begin @(negedge clk);bias_addr=a;bias_data=v;bias_we=1;
      @(negedge clk);bias_we=0;end
  endtask
  task infer_and_check;
    input signed [7:0] x;
    input signed [7:0] score0,score1;
    input [2:0] winner;
    integer cycles;
    begin
      @(negedge clk);features=0;features[7:0]=x;start=1;
      @(negedge clk);start=0;features=0;
      if(busy!==1) $fatal(1,"busy not asserted at dispatch");
      cycles=0;
      while(valid!==1'b1 && cycles<200) begin @(negedge clk);cycles=cycles+1;end
      if(valid!==1'b1 || error!==0) $fatal(1,"inference failed, cycles=%0d",cycles);
      if(outputs!=={48'd0,score1[7:0],score0[7:0]} || predicted_class!==winner)
        $fatal(1,"bad scores x=%0d got=%h class=%0d expected=%d %d class=%0d",x,outputs,predicted_class,score0,score1,winner);
      @(negedge clk);
      if(valid!==0 || busy!==0) $fatal(1,"valid/busy handshake incorrect");
    end
  endtask
  task invalid_config;
    integer clocks;
    begin
      @(negedge clk);start=1;
      @(negedge clk);start=0;
      clocks=0;
      while(valid!==1'b1 && clocks<8) begin @(negedge clk);clocks=clocks+1;end
      if(valid!==1'b1 || error!==1 || busy!==0)
        $fatal(1,"invalid topology not rejected");
      @(negedge clk);
    end
  endtask
  initial begin
    repeat(4) @(negedge clk);rst=0;
    // Two known signed INT8 weights at layer 0, neuron 0 and neuron 1.
    write_weight(12'd0,8'sd2);
    write_weight(12'd32,8'sd3);
    write_bias(7'd0,32'sd0);
    write_bias(7'd1,32'sd0);
    infer_and_check(8'sd10,8'sd20,8'sd30,3'd1);
    infer_and_check(-8'sd10,-8'sd20,-8'sd30,3'd0);
    infer_and_check(8'sd0,8'sd0,8'sd0,3'd0); // lowest-index tie
    // Illegal topologies are rejected without touching memories.
    layer_count=0;invalid_config();layer_count=1;
    size0=9;invalid_config();size0=2;
    input_size=0;invalid_config();input_size=1;
    // Memory writes during active inference must be discarded.
    @(negedge clk);features=0;features[7:0]=8'd10;start=1;
    @(negedge clk);start=0;
    if(!busy) $fatal(1,"missing busy before forbidden write");
    weight_addr=12'd32;weight_data=8'sd99;weight_we=1;
    @(negedge clk);weight_we=0;
    begin: wait_done
      integer elapsed;
      elapsed=0;
      while(valid!==1'b1 && elapsed<200) begin @(negedge clk);elapsed=elapsed+1;end
      if(valid!==1 || error!==0 || outputs[15:0]!==16'h1e14)
        $fatal(1,"invalid write altered active inference");
    end
    @(negedge clk);
    infer_and_check(8'sd10,8'sd20,8'sd30,3'd1);
    // Reset state, but not the already-programmed SRAM contents.
    @(negedge clk);rst=1;
    @(negedge clk);rst=0;
    infer_and_check(8'sd10,8'sd20,8'sd30,3'd1);
    $display("NPU IP CORNER CASES PASS: signed, ties, invalid config, busy-write, reset");
    $finish;
  end
  initial begin #200000; $fatal(1,"corner-case watchdog"); end
endmodule
