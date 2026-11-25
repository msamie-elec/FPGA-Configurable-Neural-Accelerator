// Stop-and-wait byte framing. Receiver has no queue for pipelined requests.
module packet_link #(
    parameter integer TIMEOUT_CYCLES = 1000000
)(
    input wire clk, rst,
    input wire rx_valid, rx_error,
    input wire [7:0] rx_byte,
    output reg tx_valid,
    output reg [7:0] tx_byte,
    input wire tx_ready,
    output wire request,
    output reg [7:0] opcode, req_len,
    output reg [1023:0] payload,
    input wire reply,
    input wire [7:0] reply_len,
    input wire [1023:0] reply_payload
);
    localparam [3:0] SYNC1=0, SYNC2=1, VERSION=2, OP=3, SEQLO=4,
        SEQHI=5, LENLO=6, LENHI=7, PAY=8, CRCLO=9, CRCHI=10,
        DISPATCH=11, WAIT_REPLY=12, SEND=13;
    reg [3:0] state;
    reg [15:0] seq, crc, tx_crc;
    reg [7:0] version, crc_lo, pos, send_len;
    reg [1023:0] send_payload;
    reg [$clog2(TIMEOUT_CYCLES+1)-1:0] gap;
    function automatic [15:0] crc16(input [15:0] initial_crc, input [7:0] octet);
        reg [15:0] c;
        integer i;
        begin
            c = initial_crc ^ {octet,8'b0};
            for (i=0;i<8;i=i+1) c = (c << 1) ^ (c[15] ? 16'h1021 : 16'h0);
            crc16 = c;
        end
    endfunction
    assign request = state == DISPATCH;
    always @* begin
        tx_valid = state == SEND;
        case (pos)
            0: tx_byte = 8'ha5;
            1: tx_byte = 8'h5a;
            2: tx_byte = 1;
            3: tx_byte = opcode | 8'h80;
            4: tx_byte = seq[7:0];
            5: tx_byte = seq[15:8];
            6: tx_byte = send_len;
            7: tx_byte = 0;
            default: begin
                if (pos == send_len + 8) tx_byte = tx_crc[7:0];
                else if (pos == send_len + 9) tx_byte = tx_crc[15:8];
                else tx_byte = send_payload[(pos-8)*8+:8];
            end
        endcase
    end
    task automatic respond(input [1023:0] bytes, input [7:0] length);
        begin
            send_payload <= bytes;
            send_len <= length;
            pos <= 0;
            tx_crc <= 16'hffff;
            state <= SEND;
        end
    endtask
    always @(posedge clk) begin
        if (rst) begin
            state <= SYNC1;
            opcode <= 0;
            seq <= 0;
            req_len <= 0;
            pos <= 0;
            gap <= 0;
            payload <= 0;
            crc <= 0;
            tx_crc <= 0;
            crc_lo <= 0;
            version <= 0;
            send_len <= 0;
            send_payload <= 0;
        end else if (state == SEND) begin
            if (tx_ready) begin
                if (pos >= 2 && pos < send_len + 8) tx_crc <= crc16(tx_crc,tx_byte);
                if (pos == send_len + 9) state <= SYNC1;
                else pos <= pos + 1;
            end
        end else if (state == DISPATCH) state <= WAIT_REPLY;
        else if (state == WAIT_REPLY) begin
            if (reply) respond(reply_payload,reply_len);
        end else if (rx_error) begin
            state <= SYNC1;
            gap <= 0;
        end else if (rx_valid) begin
            gap <= 0;
            if (state >= OP && state <= PAY) crc <= crc16(crc,rx_byte);
            case (state)
                SYNC1: if (rx_byte == 8'ha5) state <= SYNC2;
                SYNC2: if (rx_byte == 8'h5a) state <= VERSION;
                       else if (rx_byte != 8'ha5) state <= SYNC1;
                VERSION: begin
                    version <= rx_byte;
                    crc <= crc16(16'hffff,rx_byte);
                    state <= OP;
                end
                OP: begin opcode <= rx_byte; state <= SEQLO; end
                SEQLO: begin seq[7:0] <= rx_byte; state <= SEQHI; end
                SEQHI: begin seq[15:8] <= rx_byte; state <= LENLO; end
                LENLO: begin req_len <= rx_byte; state <= LENHI; end
                LENHI: begin
                    pos <= 0;
                    if (rx_byte != 0 || req_len > 128) respond(1024'd2,8'd1);
                    else state <= req_len == 0 ? CRCLO : PAY;
                end
                PAY: begin
                    payload[pos*8+:8] <= rx_byte;
                    if (pos + 1 == req_len) state <= CRCLO;
                    else pos <= pos + 1;
                end
                CRCLO: begin crc_lo <= rx_byte; state <= CRCHI; end
                CRCHI: begin
                    if ({rx_byte,crc_lo} != crc) respond(1024'd1,8'd1);
                    else if (version != 1) respond(1024'd3,8'd1);
                    else state <= DISPATCH;
                end
                default: state <= SYNC1;
            endcase
        end else if (state != SYNC1) begin
            if (gap == TIMEOUT_CYCLES-1) begin
                state <= SYNC1;
                gap <= 0;
            end else gap <= gap + 1;
        end
    end
endmodule
