`timescale 1ns/1ps
module tb_npu_scalable;
  reg clk=0;
  always #5 clk=~clk;
  reg rst=1,start=0,weight_we=0,bias_we=0;
  reg [255:0] features=0;
  reg [2:0] layer_count=0;
  reg [5:0] input_size=0,size0=0,size1=0,size2=0,size3=0;
  reg [3:0] shift=4;
  reg [11:0] weight_addr=0;
  reg signed [7:0] weight_data=0;
  reg [6:0] bias_addr=0;
  reg signed [31:0] bias_data=0;
  wire busy,valid,error;
  wire [2:0] predicted_class;
  wire [63:0] outputs;
  reg [7:0] weight_image[0:4095];
  reg [31:0] bias_image[0:127];
  reg [324:0] records[0:47];
  integer i,cycles,mode;

  npu_scalable_core dut (
    .clk(clk),.rst(rst),.start(start),.features(features),
    .layer_count(layer_count),.input_size(input_size),
    .size0(size0),.size1(size1),.size2(size2),.size3(size3),
    .shift(shift),
    .weight_we(weight_we),.weight_addr(weight_addr),.weight_data(weight_data),
    .bias_we(bias_we),.bias_addr(bias_addr),.bias_data(bias_data),
    .busy(busy),.valid(valid),.error(error),
    .predicted_class(predicted_class),.outputs(outputs)
  );

  task configure;
    input integer selection;
    begin
      case(selection)
        0:begin
          layer_count=3;input_size=4;
          size0=8;size1=4;size2=2;size3=1;
        end
        1:begin
          layer_count=3;input_size=8;
          size0=16;size1=8;size2=2;size3=1;
        end
        default:begin
          layer_count=4;input_size=32;
          size0=32;size1=32;size2=32;size3=8;
        end
      endcase
    end
  endtask

  initial begin
    $readmemh("build/scalable_weights.hex",weight_image);
    $readmemh("build/scalable_biases.hex",bias_image);
    $readmemh("build/scalable_vectors.hex",records);
    repeat(4) @(negedge clk);
    rst=0;
    for(i=0;i<4096;i=i+1) begin
      @(negedge clk);
      weight_we=1;
      weight_addr=i;
      weight_data=weight_image[i];
    end
    @(negedge clk);weight_we=0;
    for(i=0;i<128;i=i+1) begin
      @(negedge clk);
      bias_we=1;
      bias_addr=i;
      bias_data=bias_image[i];
    end
    @(negedge clk);bias_we=0;
    for(i=0;i<48;i=i+1) begin
      mode=records[i][324:323];
      configure(mode);
      @(negedge clk);
      features=records[i][322:67];
      start=1;
      @(negedge clk);
      start=0;
      features=0; // proves input snapshot is retained after start
      if(busy!==1) $fatal(1,"busy missing for test %0d",i);
      cycles=0;
      while(valid!==1'b1 && cycles<5000) begin
        @(negedge clk);
        cycles=cycles+1;
      end
      if(valid!==1'b1 || error!==0)
        $fatal(1,"timeout/error test=%0d mode=%0d elapsed=%0d",i,mode,cycles);
      if(outputs!==records[i][66:3] ||
         predicted_class!==records[i][2:0])
        $fatal(1,"mismatch test=%0d mode=%0d got out=%h class=%0d expected out=%h class=%0d",
          i,mode,outputs,predicted_class,records[i][66:3],records[i][2:0]);
      @(negedge clk);
      if(valid!==0 || busy!==0) $fatal(1,"bad done handshake test=%0d",i);
    end
    $display("SCALABLE NPU PASS: 48 Python-golden cases, widths 4/8/32, max 104 neurons");
    $finish;
  end
endmodule
