module protocol_tb;
    parameter integer LANES=4, SERIAL=0;
    localparam integer TEST_HZ = SERIAL==2 ? 100000000 : 1843200;
    localparam integer BIT_CLKS=(TEST_HZ+57600)/115200;
    reg clk=0, rst=1, rx_pin=1, rx_valid=0, rx_error=0;
    reg [7:0] rx_byte=0;
    wire [7:0] tx_byte;
    wire tx_valid, busy, model_valid, result_valid;
    reg fast_ready=0;
    integer sent=0, received=0;
    always #5 clk=~clk;

    generate if (SERIAL) begin : serial_path
        wire tx_pin;
        reg valid=0;
        reg [7:0] captured;
        integer bit_index;
        npu_top #(LANES,TEST_HZ,115200) dut(clk,rst,rx_pin,tx_pin,
            busy,model_valid,result_valid);
        assign tx_valid=valid;
        assign tx_byte=captured;
        initial forever begin
            @(negedge tx_pin);
            if (!rst) begin
                repeat (BIT_CLKS/2) @(posedge clk);
                if (tx_pin !== 0) $fatal(1,"UART start bit");
                for (bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                    repeat (BIT_CLKS) @(posedge clk);
                    captured[bit_index]=tx_pin;
                end
                repeat (BIT_CLKS) @(posedge clk);
                if (tx_pin !== 1) $fatal(1,"UART stop bit");
                valid=1;
                @(posedge clk);
                valid=0;
            end
        end
    end else begin : byte_path
        wire request, reply;
        wire [7:0] opcode, req_len, reply_len;
        wire [1023:0] payload, reply_payload;
        packet_link #(64) link(clk,rst,rx_valid,rx_error,rx_byte,tx_valid,
            tx_byte,fast_ready,request,opcode,req_len,payload,reply,reply_len,reply_payload);
        npu_commands #(LANES) dut(clk,rst,request,opcode,req_len,payload,
            reply,reply_len,reply_payload,busy,model_valid,result_valid);
        always @(posedge clk) if (!rst) begin
            if (busy && !model_valid) $fatal(1,"Uncommitted model executing");
            if (dut.weight_write && dut.engine_weight_rd) $fatal(1,"Weight port collision");
            if (dut.bias_write && dut.engine_bias_rd) $fatal(1,"Bias port collision");
            if (dut.input_write && busy) $fatal(1,"Input mutation during inference");
        end
    end endgenerate

    task automatic send_byte(input [7:0] data);
        integer i;
        begin
            if (SERIAL) begin
                rx_pin=0;
                repeat (BIT_CLKS) @(negedge clk);
                for (i=0;i<8;i=i+1) begin
                    rx_pin=data[i];
                    repeat (BIT_CLKS) @(negedge clk);
                end
                rx_pin=1;
                repeat (BIT_CLKS) @(negedge clk);
            end else begin
                rx_byte=data;
                rx_valid=1;
                @(negedge clk);
                rx_valid=0;
                repeat ((sent % 3)+1) @(negedge clk);
            end
            sent=sent+1;
        end
    endtask

    task automatic expect_byte(input [7:0] data, input integer event_index);
        integer waited, i;
        reg [7:0] captured;
        begin
            waited=0;
            while (!tx_valid && waited<12000) begin
                @(negedge clk);
                waited=waited+1;
            end
            if (!tx_valid || tx_byte !== data)
                $fatal(1,"event=%0d sent=%0d received=%0d valid=%b expected=%h actual=%h",
                    event_index,sent,received,tx_valid,data,tx_byte);
            if (!SERIAL) begin
                captured=tx_byte;
                for (i=0;i<received%4;i=i+1) begin
                    @(negedge clk);
                    if (!tx_valid || tx_byte !== captured) $fatal(1,"TX changed under stall");
                end
                fast_ready=1;
                @(negedge clk);
                fast_ready=0;
            end else @(negedge clk);
            received=received+1;
        end
    endtask

    reg [11:0] events [0:299999];
    reg [4095:0] filename;
    integer count, j, waited;
    initial begin
        if (!$value$plusargs("EVENTS=%s",filename) || !$value$plusargs("COUNT=%d",count))
            $fatal(1,"EVENTS and COUNT required");
        $readmemh(filename,events,0,count-1);
        repeat (5) @(negedge clk);
        rst=0;
        repeat (5) @(negedge clk);
        for(j=0;j<count;j=j+1) begin
            case(events[j][11:8])
                0: send_byte(events[j][7:0]);
                1: expect_byte(events[j][7:0],j);
                2: if (events[j][1]) begin
                       if (!busy) $fatal(1,"Reset test requires active inference");
                       rst=1;
                       repeat (4) @(negedge clk);
                       rst=0;
                       repeat (4) @(negedge clk);
                       if (model_valid || result_valid || busy) $fatal(1,"Reset leaked state");
                   end else if (events[j][0]) repeat (80) @(negedge clk);
                   else begin
                       waited=0;
                       while (!result_valid && waited<30000) begin
                           @(negedge clk);
                           waited=waited+1;
                       end
                       if (!result_valid || busy) $fatal(1,"Inference failed to finish");
                   end
                default: $fatal(1,"Unexpected event");
            endcase
        end
        $display("PASS protocol P=%0d SERIAL=%0d sent=%0d received=%0d",
            LANES,SERIAL,sent,received);
        $finish;
    end
endmodule
