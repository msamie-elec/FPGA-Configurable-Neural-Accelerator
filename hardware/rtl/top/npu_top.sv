module npu_top #(parameter integer LANES=4, CLOCK_HZ=100000000, BAUD=115200)(
    input wire clk, rst, uart_rx,
    output wire uart_tx, busy, model_valid, result_valid
);
    wire rx_valid, rx_error, tx_valid, tx_ready, request, reply;
    wire [7:0] rx_byte, tx_byte, opcode, req_len, reply_len;
    wire [1023:0] payload, reply_payload;
    uart #(CLOCK_HZ,BAUD) serial(clk,rst,uart_rx,uart_tx,rx_valid,rx_error,rx_byte,
        tx_valid,tx_byte,tx_ready);
    packet_link #(CLOCK_HZ/10) link(clk,rst,rx_valid,rx_error,rx_byte,
        tx_valid,tx_byte,tx_ready,request,opcode,req_len,payload,
        reply,reply_len,reply_payload);
    npu_commands #(LANES,CLOCK_HZ) commands(clk,rst,request,opcode,req_len,payload,
        reply,reply_len,reply_payload,busy,model_valid,result_valid);
endmodule
