// RTL activity stimulus for three non-overlapping power phases.
// Testbench path /tb_npu_power_activity/u_bridge/accelerator intentionally
// mirrors routed UART top path u_bridge/accelerator for SAIF matching.
// Only the NPU CORE is simulated: UART and board-level activity remain
// vectorless in the annotated report. This is NOT a physical power reading.
`timescale 1ns/1ps
module tb_npu_power_activity;
  reg clk=0;
  always #5 clk=~clk;  // 100 MHz
  reg rst=1,start=0,weight_we=0,bias_we=0;
  reg [255:0] features=0;
  reg [2:0] layer_count=4;
  reg [5:0] input_size=32,size0=32,size1=32,size2=32,size3=8;
  reg [3:0] shift=6;
  reg [11:0] weight_addr=0;
  reg signed [7:0] weight_data=0;
  reg [6:0] bias_addr=0;
  reg signed [31:0] bias_data=0;
  wire busy,valid,error;
  wire [2:0] predicted_class;
  wire [63:0] outputs;
  integer n,cycles,done_count=0;
  reg [31:0] prng=32'h75c29a3e;
  integer phase=0; // 0 reset, 1 idle, 2 load, 3 inference, 4 finish

  // Mirrored instance names aid mapping, but synthesis may transform names.
  npu_power_bridge u_bridge(
    .clk(clk),.rst(rst),.start(start),.features(features),
    .layer_count(layer_count),.input_size(input_size),
    .size0(size0),.size1(size1),.size2(size2),.size3(size3),.shift(shift),
    .weight_we(weight_we),.weight_addr(weight_addr),.weight_data(weight_data),
    .bias_we(bias_we),.bias_addr(bias_addr),.bias_data(bias_data),
    .busy(busy),.valid(valid),.error(error),
    .predicted_class(predicted_class),.outputs(outputs)
  );

  initial begin
    repeat(10) @(negedge clk); rst=0;
    // A $stop marker lets Vivado Tcl capture only this steady-state window.
    phase=1;$display("POWER_READY_IDLE");$stop;
    repeat(1000) @(negedge clk);
    $display("POWER_END_IDLE");$stop;

    phase=2;$display("POWER_READY_MODEL_LOAD");$stop;
    for(n=0;n<4096;n=n+1) begin
      @(negedge clk);
      weight_we=1;weight_addr=n;
      weight_data=$signed((n*37+11)&255);
    end
    @(negedge clk);weight_we=0;
    for(n=0;n<128;n=n+1) begin
      @(negedge clk);
      bias_we=1;bias_addr=n;bias_data=$signed(n*9-400);
    end
    @(negedge clk);bias_we=0;
    $display("POWER_END_MODEL_LOAD");$stop;

    phase=3;$display("POWER_READY_INFERENCE");$stop;
    // 16 consecutive, differently stimulated maximal-network inferences.
    // The measured window includes short handshake intervals between jobs.
    for(n=0;n<16;n=n+1) begin
      @(negedge clk);
      prng={prng[30:0],prng[31]^prng[21]^prng[1]^prng[0]};
      features={features[223:0],prng};
      start=1;
      @(negedge clk);start=0;
      cycles=0;
      while(valid!==1'b1 && cycles<10000) begin
        @(negedge clk);
        cycles=cycles+1;
      end
      if(valid!==1'b1 || error!==1'b0) $fatal(1,"POWER INFER FAILED %0d",n);
      done_count=done_count+1;
      repeat(2) @(negedge clk);
    end
    if(done_count!=16) $fatal(1,"INCOMPLETE POWER PHASE");
    $display("POWER_END_INFERENCE %0d",done_count);$stop;
    phase=4;
    $display("POWER_ACTIVITY_PHASES_PASS");
    $finish;
  end
  initial begin
    #10000000;
    $fatal(1,"Power activity testbench watchdog");
  end
endmodule

// Testbench-only wrapper: matches the hardware UART bridge's core instance
// name but is not a byte-level UART simulation or board-level power study.
module npu_power_bridge(
  input wire clk,rst,start, input wire [255:0] features,
  input wire [2:0] layer_count,
  input wire [5:0] input_size,size0,size1,size2,size3,
  input wire [3:0] shift,
  input wire weight_we, input wire [11:0] weight_addr,
  input wire signed [7:0] weight_data,
  input wire bias_we, input wire [6:0] bias_addr,
  input wire signed [31:0] bias_data,
  output wire busy,valid,error,
  output wire [2:0] predicted_class,output wire [63:0] outputs
);
  npu_scalable_core accelerator(
    .clk(clk),.rst(rst),.start(start),.features(features),
    .layer_count(layer_count),.input_size(input_size),
    .size0(size0),.size1(size1),.size2(size2),.size3(size3),.shift(shift),
    .weight_we(weight_we),.weight_addr(weight_addr),.weight_data(weight_data),
    .bias_we(bias_we),.bias_addr(bias_addr),.bias_data(bias_data),
    .busy(busy),.valid(valid),.error(error),
    .predicted_class(predicted_class),.outputs(outputs)
  );
endmodule
