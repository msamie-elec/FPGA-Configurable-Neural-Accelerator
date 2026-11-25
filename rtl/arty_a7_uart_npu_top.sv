// Integrated experimental UART-to-NPU top for Digilent Arty A7-35T.
// The v0.1 switch/LED top remains available separately.
module arty_a7_uart_npu_top (
  input wire clk100,
  input wire uart_rx,
  output wire uart_tx,
  input wire [1:0] btn,
  output wire [3:0] led
);
  reg [1:0] reset_ff=2'b11;
  always @(posedge clk100) reset_ff<={reset_ff[0],btn[1]};
  wire rst=reset_ff[1];
  wire busy;
  wire [2:0] predicted;
  wire result_seen;
  npu_uart_bridge #(.CLOCK_HZ(100000000),.BAUD(115200)) u_bridge(
    .clk(clk100),.rst(rst),
    .serial_rx(uart_rx),.serial_tx(uart_tx),
    .npu_busy(busy),
    .last_class(predicted),.result_seen(result_seen)
  );
  assign led[0]=result_seen && predicted==0;
  assign led[1]=result_seen && predicted==1;
  assign led[2]=result_seen;
  assign led[3]=busy;
endmodule
