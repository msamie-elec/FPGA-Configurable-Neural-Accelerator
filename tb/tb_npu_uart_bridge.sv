`timescale 1ns/1ps
module tb_npu_uart_bridge;
  reg clk=0;
  always #5 clk=~clk;
  reg rst=1,pc_tx=1;
  wire fpga_tx,core_busy,result_seen;
  wire [2:0] last_class;
  reg [7:0] payload [0:31];
  reg [7:0] received[0:12];
  integer i;
  reg [7:0] sum,received_byte;
  npu_uart_bridge #(.CLOCK_HZ(1000000),.BAUD(100000)) dut (
    .clk(clk),.rst(rst),.serial_rx(pc_tx),.serial_tx(fpga_tx),
    .npu_busy(core_busy),.last_class(last_class),.result_seen(result_seen)
  );
  task send_byte;
    input [7:0] val;
    integer b;
    begin
      @(negedge clk);pc_tx=0;
      repeat(10) @(negedge clk);
      for(b=0;b<8;b=b+1) begin
        pc_tx=val[b];
        repeat(10) @(negedge clk);
      end
      pc_tx=1;
      repeat(9) @(negedge clk);
    end
  endtask
  task read_byte;
    output [7:0] val;
    integer b;
    begin
      @(negedge fpga_tx);
      repeat(15) @(posedge clk);
      for(b=0;b<8;b=b+1) begin
        val[b]=fpga_tx;
        repeat(10) @(posedge clk);
      end
    end
  endtask
  task command;
    input [7:0] command_id;
    input integer len;
    input integer corrupt;
    integer b;
    reg [7:0] xor_val;
    begin
      xor_val=command_id;
      send_byte(8'ha5);
      send_byte(command_id);
      for(b=0;b<len;b=b+1) begin
        send_byte(payload[b]);
        xor_val=xor_val ^ payload[b];
      end
      send_byte(xor_val ^ corrupt);
      for(b=0;b<13;b=b+1)
        read_byte(received[b]);
      if(received[0]!==8'h5a || received[1]!==command_id)
        $fatal(1,"bad response header: cmd=%h got %h %h",command_id,received[0],received[1]);
      xor_val=0;
      for(b=1;b<12;b=b+1) xor_val=xor_val^received[b];
      if(xor_val!==received[12])
        $fatal(1,"response checksum incorrect: %h expected %h",received[12],xor_val);
      repeat(2) @(negedge clk);
    end
  endtask
  initial begin
    repeat(8) @(negedge clk);rst=0;
    // Simple one-input, two-output network:
    // score0=2*x0; score1=3*x0. x0=10 => 20,30; argmax 1.
    payload[0]=0;payload[1]=0;payload[2]=2;
    command(8'h57,3,0);if(received[2]!==0) $fatal(1,"weight 0 NACK");
    payload[0]=32;payload[1]=0;payload[2]=3;
    command(8'h57,3,0);if(received[2]!==0) $fatal(1,"weight 1 NACK");
    payload[0]=0;payload[1]=0;payload[2]=0;payload[3]=0;payload[4]=0;
    command(8'h42,5,0);if(received[2]!==0) $fatal(1,"bias 0 NACK");
    payload[0]=1;
    command(8'h42,5,0);if(received[2]!==0) $fatal(1,"bias 1 NACK");
    // One computational layer, two outputs, no scaling.
    payload[0]=1;payload[1]=1;payload[2]=2;payload[3]=1;
    payload[4]=1;payload[5]=1;payload[6]=0;
    command(8'h43,7,0);if(received[2]!==0) $fatal(1,"config NACK");
    // Check that corrupt checksum produces explicit NACK.
    command(8'h50,0,8'hff);
    if(received[2]!==1) $fatal(1,"checksum error not detected");
    for(i=0;i<32;i=i+1) payload[i]=0;
    payload[0]=10;
    command(8'h49,32,0);
    if(received[2]!==0 || received[3]!==1 ||
       received[4]!==20 || received[5]!==30 ||
       !result_seen || last_class!==1)
      $fatal(1,"inference mismatch status=%d class=%d scores=%d,%d",
             received[2],received[3],received[4],received[5]);
    command(8'h50,0,0);
    if(received[2]!==0) $fatal(1,"ping failed");
    $display("UART BRIDGE PASS: weights, biases, config, checksum rejection, inference, response, ping");
    $finish;
  end
  initial begin
    #10000000;
    $fatal(1,"UART test watchdog");
  end
endmodule
