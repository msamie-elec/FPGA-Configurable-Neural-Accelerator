// Application-independent, reusable Vivado Catalog IP wrapper (v1.0).
// Bare synchronous request/control/status interface, NOT AXI4/AXI4-Lite.
// Clock is 100 MHz nominal on demonstrated Artix-7 build; positive-edge.
// Weight and bias RAM intentionally have no power-up initialisation.
// Only program when busy==0, then pulse start for a single cycle.
// Input feature0=features[7:0]; output score0=outputs[7:0].
module npu_accelerator_ip (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [255:0] features,
    input wire [2:0] layer_count,
    input wire [5:0] input_size,
    input wire [5:0] size0,
    input wire [5:0] size1,
    input wire [5:0] size2,
    input wire [5:0] size3,
    input wire [3:0] shift,
    input wire weight_we,
    input wire [11:0] weight_addr,
    input wire signed [7:0] weight_data,
    input wire bias_we,
    input wire [6:0] bias_addr,
    input wire signed [31:0] bias_data,
    output wire busy,
    output wire valid,
    output wire error,
    output wire [2:0] predicted_class,
    output wire [63:0] outputs
);
  npu_scalable_core u_core (
    .clk(clk), .rst(rst), .start(start),
    .features(features),
    .layer_count(layer_count), .input_size(input_size),
    .size0(size0), .size1(size1), .size2(size2), .size3(size3),
    .shift(shift),
    .weight_we(weight_we), .weight_addr(weight_addr), .weight_data(weight_data),
    .bias_we(bias_we), .bias_addr(bias_addr), .bias_data(bias_data),
    .busy(busy), .valid(valid), .error(error),
    .predicted_class(predicted_class), .outputs(outputs)
  );
endmodule
