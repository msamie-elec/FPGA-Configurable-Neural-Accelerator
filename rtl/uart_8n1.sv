// 8N1 UART receiver, asynchronous input synchronised to clk.
// CLOCK_HZ and BAUD integer divider; use 100 MHz / 115200 by default.
module uart_rx #(
    parameter integer CLOCK_HZ=100000000,
    parameter integer BAUD=115200
)(
    input wire clk,rst,rx,
    output reg [7:0] data,
    output reg valid
);
    localparam integer DIV = (CLOCK_HZ+BAUD/2)/BAUD;
    localparam integer HALF = DIV/2;
    reg [1:0] sync_rx=2'b11;
    reg [1:0] state=0;
    reg [15:0] tick=0;
    reg [2:0] bit_idx=0;
    reg [7:0] work=0;
    always @(posedge clk) begin
        sync_rx <= {sync_rx[0],rx};
        if(rst) begin
            state<=0;tick<=0;bit_idx<=0;
            data<=0;valid<=0;
        end else begin
            valid<=0;
            case(state)
                0: if(!sync_rx[1]) begin tick<=HALF-1;state<=1;end
                1: if(tick==0) begin
                       if(!sync_rx[1]) begin
                           tick<=DIV-1;bit_idx<=0;state<=2;
                       end else state<=0;
                   end else tick<=tick-1'b1;
                2: if(tick==0) begin
                       work[bit_idx]<=sync_rx[1];tick<=DIV-1;
                       if(bit_idx==7) state<=3;
                       else bit_idx<=bit_idx+1'b1;
                   end else tick<=tick-1'b1;
                3: if(tick==0) begin
                       if(sync_rx[1]) begin
                           data<=work;valid<=1;
                       end
                       state<=0;
                   end else tick<=tick-1'b1;
            endcase
        end
    end
endmodule

// 8N1 UART transmitter; start is a one-clock pulse when busy==0.
module uart_tx #(
    parameter integer CLOCK_HZ=100000000,
    parameter integer BAUD=115200
)(
    input wire clk,rst,
    input wire start,
    input wire [7:0] data,
    output reg tx,
    output reg busy
);
    localparam integer DIV = (CLOCK_HZ+BAUD/2)/BAUD;
    reg [9:0] frame=10'h3ff;
    reg [15:0] tick=0;
    reg [3:0] index=0;
    always @(posedge clk) begin
        if(rst) begin tx<=1;busy<=0;tick<=0;index<=0;frame<=10'h3ff;end
        else if(!busy) begin
            tx<=1;
            if(start) begin
                frame<={1'b1,data,1'b0};
                tx<=0;tick<=DIV-1;index<=0;busy<=1;
            end
        end else if(tick==0) begin
            if(index==9) begin tx<=1;busy<=0;end
            else begin
                index<=index+1'b1;
                tx<=frame[index+1];
                tick<=DIV-1;
            end
        end else tick<=tick-1'b1;
    end
endmodule
