module uart #(parameter integer CLOCK_HZ=100000000, BAUD=115200)(
    input wire clk, rst, rx,
    output reg tx,
    output reg rx_valid, rx_error,
    output reg [7:0] rx_byte,
    input wire tx_valid,
    input wire [7:0] tx_byte,
    output wire tx_ready
);
    localparam integer PERIOD = (CLOCK_HZ + BAUD/2)/BAUD;
    localparam integer CW = $clog2(PERIOD+1);
    localparam [1:0] IDLE=0, START=1, DATA=2, STOP=3;
    (* ASYNC_REG="TRUE" *) reg rx_meta, rx_sync;
    reg [1:0] rx_state;
    reg [CW-1:0] rx_timer, tx_timer;
    reg [2:0] rx_bit;
    reg [3:0] tx_left;
    reg [9:0] tx_shift;
    assign tx_ready = tx_left == 0;

    always @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
        rx_valid <= 0;
        rx_error <= 0;
        if (rst) begin
            rx_state <= IDLE;
            rx_timer <= 0;
            rx_bit <= 0;
            rx_byte <= 0;
            tx <= 1;
            tx_left <= 0;
            tx_timer <= 0;
            tx_shift <= 10'h3ff;
        end else begin
            if (rx_state == IDLE) begin
                if (!rx_sync) begin
                    rx_timer <= PERIOD/2-1;
                    rx_state <= START;
                end
            end else if (rx_timer != 0) rx_timer <= rx_timer - 1;
            else begin
                rx_timer <= PERIOD-1;
                case (rx_state)
                    START: begin
                        rx_bit <= 0;
                        rx_state <= rx_sync ? IDLE : DATA;
                    end
                    DATA: begin
                        rx_byte[rx_bit] <= rx_sync;
                        rx_bit <= rx_bit + 1;
                        if (rx_bit == 7) rx_state <= STOP;
                    end
                    STOP: begin
                        rx_error <= !rx_sync;
                        rx_valid <= rx_sync;
                        rx_state <= IDLE;
                    end
                    default: rx_state <= IDLE;
                endcase
            end
            if (tx_ready) begin
                if (tx_valid) begin
                    tx <= 0;
                    tx_shift <= {1'b1,1'b1,tx_byte};
                    tx_left <= 10;
                    tx_timer <= PERIOD-1;
                end
            end else if (tx_timer != 0) tx_timer <= tx_timer - 1;
            else begin
                tx <= tx_shift[0];
                tx_shift <= {1'b1,tx_shift[9:1]};
                tx_left <= tx_left - 1;
                tx_timer <= PERIOD-1;
            end
        end
    end
endmodule
