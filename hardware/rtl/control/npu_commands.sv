module npu_commands #(parameter integer LANES=4, CLOCK_HZ=100000000)(
    input wire clk, rst, request,
    input wire [7:0] opcode, req_len,
    input wire [1023:0] payload,
    output reg reply,
    output reg [7:0] reply_len,
    output reg [1023:0] reply_payload,
    output wire busy, model_valid, result_valid
);
    localparam [7:0] OK=0, BAD_LEN=2, UNSUPPORTED=4, BUSY=5, NO_MODEL=6,
        MODEL_INVALID=7, OUT_OF_RANGE=8, BAD_SEQUENCE=9, INPUT_INCOMPLETE=10,
        RESULT_NOT_READY=11;
    localparam [3:0] IDLE=0, IMAGE=1, INPUT_BYTES=2, CHECK_HEADER=3,
        CHECK_DESC=4, BIAS_READ=5, CHECK_BIAS=6, RESULT_READ=7, RESULT_SAVE=8;
    localparam integer MAX_IMAGE=32+128+16384+4096+32;
    reg [3:0] state;
    reg [255:0] header, descriptors [0:3];
    reg [63:0] quants [0:3];
    reg committed, loading, staged, input_open, ready_result, start_engine;
    reg model_error;
    reg [14:0] image_len, image_pos;
    reg [31:0] expected_crc, image_crc;
    reg [8:0] input_len, input_pos;
    reg [7:0] cursor, chunk_end, page_count;
    reg [8:0] page_index;
    reg [4:0] page_pos;
    reg [1:0] check_layer;
    reg [8:0] check_neuron;
    reg [14:0] checked_weights;
    reg [12:0] checked_biases;
    reg [7:0] previous_status;
    reg [31:0] job_id;

    wire [7:0] layer_total = header[55:48];
    wire [15:0] first_input = header[79:64], final_output = header[95:80];
    wire [31:0] desc_bytes = header[127:96], weight_bytes = header[159:128],
        bias_bytes = header[191:160], quant_bytes = header[223:192];
    wire sane_layout = layer_total >= 1 && layer_total <= 4 &&
        desc_bytes == {19'd0,layer_total,5'd0} &&
        weight_bytes <= 16384 && weight_bytes[2:0] == 0 &&
        bias_bytes <= 4096 && bias_bytes[1:0] == 0 &&
        quant_bytes == {21'd0,layer_total,3'd0};
    wire [14:0] desc_end = 15'd32 + desc_bytes[14:0];
    wire [14:0] weight_end = desc_end + weight_bytes[14:0];
    wire [14:0] bias_end = weight_end + bias_bytes[14:0];
    wire [14:0] weight_offset = image_pos - desc_end;
    wire [14:0] bias_offset = image_pos - weight_end;
    wire [14:0] quant_offset = image_pos - bias_end;
    wire [14:0] desc_offset = image_pos - 15'd32;
    wire [7:0] octet = payload[cursor[6:0]*8+:8];
    wire weight_write = state == IMAGE && sane_layout && image_pos >= desc_end &&
        image_pos < weight_end;
    wire bias_write = state == IMAGE && sane_layout && image_pos >= weight_end &&
        image_pos < bias_end;

    wire [1:0] engine_layer;
    wire validating = state == CHECK_DESC || state == BIAS_READ || state == CHECK_BIAS;
    wire [1:0] selected = validating ? check_layer : engine_layer;
    wire [255:0] desc = descriptors[selected];
    wire [63:0] quant = quants[selected];
    wire [15:0] di = desc[47:32], dout = desc[63:48], stride = desc[175:160];
    wire [31:0] dw = desc[95:64], db = desc[127:96], dq = desc[159:128];
    wire [1:0] prior_layer = check_layer-2'd1;
    wire [15:0] expected_input = check_layer == 0 ? first_input :
        descriptors[prior_layer][63:48];
    wire final_desc = {1'b0,check_layer}+3'd1 == layer_total;
    wire [14:0] row_weight_span = dout[8:0] * stride[5:0];
    wire [17:0] next_weights = {3'd0,checked_weights} + {row_weight_span,3'b0};
    wire [13:0] next_biases = {1'b0,checked_biases} + {3'd0,dout[8:0],2'b0};
    wire [9:0] rounded_dim = {1'b0,di[8:0]}+10'd7;
    wire valid_desc = desc[7:0] == (final_desc ? 8'd2 : 8'd1) &&
        desc[31:8] == 0 && desc[255:176] == 0 &&
        di >= 1 && di <= 256 && dout >= 1 && dout <= 256 &&
        di == expected_input && (!final_desc || dout == final_output) &&
        stride == {9'd0,rounded_dim[9:3]} &&
        dw == {17'd0,checked_weights} && db == {19'd0,checked_biases} &&
        dq == {27'd0,check_layer,3'b0} &&
        next_weights <= weight_bytes && next_biases <= bias_bytes &&
        (!final_desc || (next_weights == weight_bytes && next_biases == bias_bytes)) &&
        (final_desc ? quant == 0 :
            (quant[63:37] == 0 && !quant[31] && quant[30:0] != 0));
    wire engine_weight_rd, engine_bias_rd, engine_busy, engine_done;
    wire [10:0] engine_weight_addr;
    wire [9:0] engine_bias_addr;
    wire [63:0] weight_data;
    wire [31:0] bias_data, result_data, cycles, issues, word_reads;
    wire [9:0] check_bias_addr = db[11:2]+{1'b0,check_neuron};
    wire [32:0] bias_magnitude = bias_data[31] ?
        -{1'b1,bias_data} : {1'b0,bias_data};
    wire [32:0] bias_bound = bias_magnitude + {10'd0,di[8:0],14'd0};
    wire input_write = state == INPUT_BYTES;
    assign busy = engine_busy || start_engine;
    assign model_valid = committed;
    assign result_valid = ready_result || engine_done;

    packed_ram #(.AW(11)) weight_ram(clk, engine_weight_rd, engine_weight_addr,
        weight_data, weight_offset[13:3],
        weight_write ? 8'b1 << weight_offset[2:0] : 8'b0, {8{octet}});
    packed_ram #(.AW(10), .BYTES(4)) bias_ram(clk, engine_bias_rd || state==BIAS_READ,
        validating ? check_bias_addr : engine_bias_addr, bias_data, bias_offset[11:2],
        bias_write ? 4'b1 << bias_offset[1:0] : 4'b0, {4{octet}});
    dense_engine #(LANES) engine(clk, rst, start_engine,
        layer_total[2:0], engine_layer, di[8:0], dout[8:0], stride[5:0], dw[13:3],
        db[11:2], quant[30:0], quant[36:32], engine_weight_rd, engine_weight_addr,
        weight_data, engine_bias_rd, engine_bias_addr, bias_data, input_write,
        input_pos[7:0], octet, state==RESULT_READ, page_index[7:0], result_data,
        engine_busy, engine_done, cycles, issues, word_reads);

    function automatic [31:0] crc32(input [31:0] initial_crc, input [7:0] byte_data);
        reg [31:0] c;
        integer i;
        begin
            c = initial_crc ^ {24'd0,byte_data};
            for(i=0;i<8;i=i+1) c = (c >> 1) ^ (c[0] ? 32'hedb88320 : 32'd0);
            crc32 = c;
        end
    endfunction
    task automatic send_status(input [7:0] code);
        begin
            reply_len <= 1;
            reply_payload <= {1016'd0,code};
            reply <= 1;
            previous_status <= code;
            state <= IDLE;
        end
    endtask
    task automatic reject_model;
        begin
            loading <= 0;
            model_error <= 1;
            send_status(MODEL_INVALID);
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            committed <= 0;
            loading <= 0;
            model_error <= 0;
            staged <= 0;
            input_open <= 0;
            ready_result <= 0;
            start_engine <= 0;
            reply <= 0;
            reply_len <= 0;
            reply_payload <= 0;
            previous_status <= 0;
            job_id <= 0;
            image_pos <= 0;
            image_len <= 0;
            input_pos <= 0;
            input_len <= 0;
            expected_crc <= 0;
            image_crc <= 32'hffffffff;
        end else begin
            reply <= 0;
            start_engine <= 0;
            if (engine_done) ready_result <= 1;
            case (state)
                IDLE: if (request) begin
                    case (opcode)
                        8'h01: if (req_len != 0) send_status(BAD_LEN);
                        else begin
                            send_status(OK);
                            reply_len <= 17;
                            reply_payload[135:8] <= {
                                8'd3,16'd4096,16'd16384,16'd256,16'd256,8'd4,
                                8'(LANES),32'(CLOCK_HZ),8'd1};
                        end
                        8'h13: if (req_len != 0) send_status(BAD_LEN);
                        else begin
                            send_status(OK);
                            reply_len <= 6;
                            reply_payload[47:8] <= {committed ? expected_crc : 32'd0,
                                5'd0,model_error,loading,committed};
                        end
                        8'h30: if (req_len != 0) send_status(BAD_LEN);
                        else begin
                            send_status(OK);
                            reply_len <= 23;
                            reply_payload[183:8] <= {
                                job_id, committed ? expected_crc : 32'd0,
                                word_reads,issues,cycles,previous_status,
                                4'd0,staged,committed,result_valid,busy};
                            previous_status <= previous_status;
                        end
                        8'h10: if (req_len != 8) send_status(BAD_LEN);
                        else if (busy) send_status(BUSY);
                        else if (payload[31:0] < 72 || payload[31:0] > MAX_IMAGE)
                            send_status(OUT_OF_RANGE);
                        else begin
                            committed <= 0;
                            staged <= 0;
                            input_open <= 0;
                            ready_result <= 0;
                            model_error <= 0;
                            loading <= 1;
                            image_pos <= 0;
                            image_len <= payload[14:0];
                            expected_crc <= payload[63:32];
                            image_crc <= 32'hffffffff;
                            send_status(OK);
                        end
                        8'h11: if (req_len < 5) send_status(BAD_LEN);
                        else if (busy) send_status(BUSY);
                        else if (!loading || payload[31:0] != {17'd0,image_pos})
                            send_status(BAD_SEQUENCE);
                        else if ({1'b0,image_pos}+{8'd0,req_len}-16'd4 > image_len)
                            send_status(OUT_OF_RANGE);
                        else begin
                            cursor <= 4;
                            chunk_end <= req_len;
                            state <= IMAGE;
                        end
                        8'h12: if (req_len != 0) send_status(BAD_LEN);
                        else if (busy) send_status(BUSY);
                        else if (!loading) send_status(BAD_SEQUENCE);
                        else if (image_pos != image_len || ~image_crc != expected_crc)
                            reject_model();
                        else state <= CHECK_HEADER;
                        8'h20: if (req_len != 2) send_status(BAD_LEN);
                        else if (busy) send_status(BUSY);
                        else if (!committed) send_status(NO_MODEL);
                        else if (payload[15:0] != first_input) send_status(OUT_OF_RANGE);
                        else begin
                            input_len <= payload[8:0];
                            input_pos <= 0;
                            input_open <= 1;
                            staged <= 0;
                            send_status(OK);
                        end
                        8'h21: if (req_len < 3) send_status(BAD_LEN);
                        else if (busy) send_status(BUSY);
                        else if (!input_open || payload[15:0] != {7'd0,input_pos})
                            send_status(BAD_SEQUENCE);
                        else if ({1'b0,input_pos}+{2'd0,req_len}-10'd2 > input_len)
                            send_status(OUT_OF_RANGE);
                        else begin
                            cursor <= 2;
                            chunk_end <= req_len;
                            state <= INPUT_BYTES;
                        end
                        8'h22: if (req_len != 0) send_status(BAD_LEN);
                        else if (busy) send_status(BUSY);
                        else if (!committed) send_status(NO_MODEL);
                        else if (!staged) send_status(INPUT_INCOMPLETE);
                        else begin
                            ready_result <= 0;
                            staged <= 0;
                            start_engine <= 1;
                            job_id <= job_id + 1;
                            send_status(OK);
                        end
                        8'h23: if (req_len != 3) send_status(BAD_LEN);
                        else if (!result_valid) send_status(RESULT_NOT_READY);
                        else if (payload[23:16] == 0 || payload[23:16] > 30 ||
                                 {1'b0,payload[15:0]}+{9'd0,payload[23:16]} > final_output)
                            send_status(OUT_OF_RANGE);
                        else begin
                            page_index <= payload[8:0];
                            page_count <= payload[23:16];
                            page_pos <= 0;
                            reply_payload <= {992'd0,payload[23:0],8'd0};
                            state <= RESULT_READ;
                        end
                        8'h7f: if (req_len != 0) send_status(BAD_LEN);
                        else if (busy) send_status(BUSY);
                        else begin
                            committed <= 0;
                            loading <= 0;
                            model_error <= 0;
                            staged <= 0;
                            input_open <= 0;
                            ready_result <= 0;
                            send_status(OK);
                        end
                        default: send_status(UNSUPPORTED);
                    endcase
                end
                IMAGE: begin
                    image_crc <= crc32(image_crc,octet);
                    if (image_pos < 32) header[image_pos[4:0]*8+:8] <= octet;
                    else if (sane_layout) begin
                        if (image_pos < desc_end)
                            descriptors[desc_offset[6:5]][desc_offset[4:0]*8+:8] <= octet;
                        else if (image_pos >= bias_end && quant_offset < quant_bytes)
                            quants[quant_offset[4:3]][quant_offset[2:0]*8+:8] <= octet;
                    end
                    image_pos <= image_pos + 1;
                    cursor <= cursor + 1;
                    if (cursor + 1 == chunk_end) send_status(OK);
                end
                INPUT_BYTES: begin
                    input_pos <= input_pos + 1;
                    cursor <= cursor + 1;
                    if (input_pos + 1 == input_len) begin
                        staged <= 1;
                        input_open <= 0;
                    end
                    if (cursor + 1 == chunk_end) send_status(OK);
                end
                CHECK_HEADER: begin
                    if (!sane_layout || header[31:0] != 32'h3155504e ||
                        header[47:32] != 16'h0001 || header[63:56] != 0 ||
                        header[255:224] != 0 || first_input < 1 || first_input > 256 ||
                        final_output < 1 || final_output > 256 ||
                        bias_end+quant_bytes != image_len) reject_model();
                    else begin
                        checked_weights <= 0;
                        checked_biases <= 0;
                        check_layer <= 0;
                        state <= CHECK_DESC;
                    end
                end
                CHECK_DESC: if (!valid_desc) reject_model();
                else begin
                    check_neuron <= 0;
                    checked_weights <= next_weights[14:0];
                    checked_biases <= next_biases[12:0];
                    state <= BIAS_READ;
                end
                BIAS_READ: state <= CHECK_BIAS;
                CHECK_BIAS: if (bias_bound > 33'd2147483647) reject_model();
                else if (check_neuron+1 < dout) begin
                    check_neuron <= check_neuron+1;
                    state <= BIAS_READ;
                end else if (final_desc) begin
                    committed <= 1;
                    loading <= 0;
                    send_status(OK);
                end else begin
                    check_layer <= check_layer+1;
                    state <= CHECK_DESC;
                end
                RESULT_READ: state <= RESULT_SAVE;
                RESULT_SAVE: begin
                    reply_payload[(page_pos+1)*32+:32] <= result_data;
                    if (page_pos+1 == page_count) begin
                        reply_len <= 4 + 4*page_count;
                        reply <= 1;
                        previous_status <= OK;
                        state <= IDLE;
                    end else begin
                        page_pos <= page_pos+1;
                        page_index <= page_index+1;
                        state <= RESULT_READ;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
