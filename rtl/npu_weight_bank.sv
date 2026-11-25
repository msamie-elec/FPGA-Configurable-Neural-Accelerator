// Synchronous single-read/single-write weight bank.
// Eight independent instances give eight weights per read cycle.
// Addressing is layer*128 + neuron*4 + input_group (512 words per bank).
module npu_weight_bank (
  input wire clk,
  input wire [8:0] read_addr,
  output reg signed [7:0] read_data,
  input wire write_enable,
  input wire [8:0] write_addr,
  input wire signed [7:0] write_data
);
  (* ram_style="block" *) reg signed [7:0] mem [0:511];
  always @(posedge clk) begin
    read_data <= mem[read_addr];
    if (write_enable) mem[write_addr] <= write_data;
  end
endmodule
