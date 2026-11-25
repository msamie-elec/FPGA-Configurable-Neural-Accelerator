module arty_a7 #(parameter integer LANES=4)(
    input wire clk100, reset_btn, uart_rx,
    output wire uart_tx,
    output wire [2:0] led
);
    (* ASYNC_REG="TRUE" *) reg [2:0] reset_pipe = 3'b111;
    always @(posedge clk100 or posedge reset_btn)
        if (reset_btn) reset_pipe <= 3'b111;
        else reset_pipe <= {reset_pipe[1:0],1'b0};
    npu_top #(LANES) accelerator(clk100,reset_pipe[2],uart_rx,uart_tx,
        led[0],led[1],led[2]);
endmodule
