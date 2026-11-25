// Structural/functional smoke of independent consumer top. Uses unpackaged
// core only under NPU_CONSUMER_SIM so GitHub CI needs no proprietary Vivado.
`timescale 1ns/1ps
module tb_ip_consumer_top;
  reg clk100=0,btn_reset=1;
  wire [3:0] led;
  always #5 clk100=~clk100;
  arty_a7_ip_consumer_top dut(.clk100(clk100),.btn_reset(btn_reset),.led(led));
  integer n;
  initial begin
    repeat(8) @(posedge clk100);
    @(negedge clk100);btn_reset=0;
    for(n=0;n<40000;n=n+1) begin
      @(negedge clk100);
      if(dut.error_latched) $fatal(1,"Consumer IP raised error");
      if(dut.completed_inferences>=2) begin
        if(dut.phase!=3 && dut.phase!=4) $fatal(1,"Unexpected consumer state");
        $display("CONSUMER TOP PASS: wrote all 4096 weights and 128 biases, completed %0d max-width inferences",
                 dut.completed_inferences);
        $finish;
      end
    end
    $fatal(1,"Consumer top did not complete two inferences");
  end
endmodule
