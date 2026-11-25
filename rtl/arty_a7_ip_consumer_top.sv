// Self-contained representative FPGA consumer for the PACKAGED NPU IP.
// NOT a production inference data source or UART board-top replacement.
// On reset, writes every weight and bias address, then runs repeated maximum
// topology inferences from evolving deterministic 256-bit test features.
// Outputs score digest and completion toggle on four Arty A7 LEDs.
// For software CI NPU_CONSUMER_SIM uses the same RTL wrapper directly; in
// Vivado the instantiated npu0 is created via packaged IP-XACT / .xci.
module arty_a7_ip_consumer_top (
  input wire clk100,
  input wire btn_reset,
  output wire [3:0] led
);
  reg [1:0] reset_sync=2'b11;
  always @(posedge clk100) reset_sync <= {reset_sync[0],btn_reset};
  wire rst=reset_sync[1];

  localparam [2:0] INIT=0, WRITE_W=1, WRITE_B=2,
                   ISSUE=3, WAIT_RESULT=4;
  reg [2:0] phase=INIT;
  reg [11:0] w_addr=0;
  reg [6:0] b_addr=0;
  reg [255:0] features=256'h0123456789abcdef_0123456789abcdef_0123456789abcdef_0123456789abcdef;
  reg [31:0] prng=32'h5a17f00d;
  reg [3:0] result_digest=0;
  reg result_toggle=0;
  reg error_latched=0;
  reg [15:0] completed_inferences=0;
  wire busy, valid, error;
  wire [2:0] predicted_class;
  wire [63:0] outputs;

  wire weight_we=(phase==WRITE_W);
  wire bias_we=(phase==WRITE_B);
  wire start=(phase==ISSUE);
  wire signed [7:0] weight_data =
      w_addr[7:0] ^ {w_addr[11:8],w_addr[3:0]} ^ prng[7:0];
  wire signed [31:0] bias_data =
      {{25{b_addr[6]}},b_addr} + $signed(prng[15:0]);
  // Reduce ALL eight output bytes into visible digest bits, avoiding
  // optimising away entire result lanes during Vivado implementation.
  wire [3:0] output_nibble_xor =
      outputs[3:0]   ^ outputs[7:4]   ^ outputs[11:8]  ^ outputs[15:12] ^
      outputs[19:16] ^ outputs[23:20] ^ outputs[27:24] ^ outputs[31:28] ^
      outputs[35:32] ^ outputs[39:36] ^ outputs[43:40] ^ outputs[47:44] ^
      outputs[51:48] ^ outputs[55:52] ^ outputs[59:56] ^ outputs[63:60];

  always @(posedge clk100) begin
    if(rst) begin
      phase<=INIT;
      w_addr<=0;
      b_addr<=0;
      features<=256'h0123456789abcdef_0123456789abcdef_0123456789abcdef_0123456789abcdef;
      prng<=32'h5a17f00d;
      result_digest<=0;
      result_toggle<=0;
      error_latched<=0;
      completed_inferences<=0;
    end else begin
      prng<={prng[30:0],prng[31]^prng[21]^prng[1]^prng[0]};
      case(phase)
        INIT: phase<=WRITE_W;
        WRITE_W: begin
          w_addr<=w_addr+1'b1;
          if(w_addr==12'hfff) phase<=WRITE_B;
        end
        WRITE_B: begin
          b_addr<=b_addr+1'b1;
          if(b_addr==7'd127) phase<=ISSUE;
        end
        ISSUE: phase<=WAIT_RESULT;
        WAIT_RESULT: if(valid) begin
          if(error) error_latched<=1'b1;
          result_digest<=result_digest ^ output_nibble_xor ^ {1'b0,predicted_class};
          result_toggle<=~result_toggle;
          completed_inferences<=completed_inferences+1'b1;
          features<={features[247:0],features[255:248]^prng[7:0]};
          phase<=ISSUE;
        end
        default:phase<=INIT;
      endcase
    end
  end

  // Demonstrated largest topology: 32→32→32→32→8.
  // IP has runtime programmable topology; this is a representative
  // fully-utilised consumer for consistent post-route measurements.
`ifdef NPU_CONSUMER_SIM
  npu_accelerator_ip u_npu (
`else
  npu0 u_npu (
`endif
    .clk(clk100),.rst(rst),.start(start),.features(features),
    .layer_count(3'd4),.input_size(6'd32),
    .size0(6'd32),.size1(6'd32),.size2(6'd32),.size3(6'd8),
    .shift(4'd6),
    .weight_we(weight_we),.weight_addr(w_addr),.weight_data(weight_data),
    .bias_we(bias_we),.bias_addr(b_addr),.bias_data(bias_data),
    .busy(busy),.valid(valid),.error(error),
    .predicted_class(predicted_class),.outputs(outputs)
  );

  assign led={error_latched,result_toggle,result_digest[1:0]};
endmodule
