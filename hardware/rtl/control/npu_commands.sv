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
        CHECK_DESC=4, BIAS_READ=5, CHECK_BIAS=6, RESULT_READ=7, RESULT_SAVE=8,
        DESC_FETCH=9, DESC_PREP=10, DESC_LIMITS=11, COMMIT_REPLY=12,
        BIAS_EVAL=13;
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
    reg [255:0] check_desc;
    reg [63:0] check_quant;
    reg [15:0] check_expected_input;
    reg check_final, commit_ok;
    reg [14:0] check_weight_span;
    reg [17:0] next_weights;
    reg [13:0] next_biases;
    reg [31:0] bias_limit;
    reg bias_in_range;
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
    reg [14:0] desc_end, weight_end, bias_end;
    reg image_layout_valid;
    wire [14:0] weight_offset = image_pos - desc_end;
    wire [14:0] bias_offset = image_pos - weight_end;
    wire [14:0] quant_offset = image_pos - bias_end;
    wire [14:0] desc_offset = image_pos - 15'd32;
    wire [7:0] octet = payload[cursor[6:0]*8+:8];
    wire weight_write = state == IMAGE && image_layout_valid && image_pos >= desc_end &&
        image_pos < weight_end;
    wire bias_write = state == IMAGE && image_layout_valid && image_pos >= weight_end &&
        image_pos < bias_end;

    wire [1:0] engine_layer;
    wire validating_bias = state == BIAS_READ;
    wire [255:0] desc = descriptors[engine_layer];
    wire [63:0] quant = quants[engine_layer];
    wire [1:0] prior_layer = check_layer-2'd1;
    wire [15:0] check_in = check_desc[47:32], check_out = check_desc[63:48],
        check_stride = check_desc[175:160];
    wire [9:0] rounded_dim = {1'b0,check_in[8:0]}+10'd7;
    wire valid_desc = check_desc[7:0] == (check_final ? 8'd2 : 8'd1) &&
        check_desc[31:8] == 0 && check_desc[255:176] == 0 &&
        check_in >= 1 && check_in <= 256 && check_out >= 1 && check_out <= 256 &&
        check_in == check_expected_input && (!check_final || check_out == final_output) &&
        check_stride == {9'd0,rounded_dim[9:3]} &&
        check_desc[95:64] == {17'd0,checked_weights} &&
        check_desc[127:96] == {19'd0,checked_biases} &&
        check_desc[159:128] == {27'd0,check_layer,3'b0} &&
        next_weights <= {3'd0,weight_bytes[14:0]} &&
        next_biases <= {1'b0,bias_bytes[12:0]} &&
        (!check_final || (next_weights == {3'd0,weight_bytes[14:0]} &&
                         next_biases == {1'b0,bias_bytes[12:0]})) &&
        (check_final ? check_quant == 0 :
            (check_quant[63:37] == 0 && !check_quant[31] && check_quant[30:0] != 0));
    wire engine_weight_rd, engine_bias_rd, engine_busy, engine_done;
    wire [10:0] engine_weight_addr;
    wire [9:0] engine_bias_addr;
    wire [63:0] weight_data;
    wire [31:0] bias_data, result_data, cycles, issues, word_reads;
    wire [9:0] check_bias_addr = check_desc[107:98]+{1'b0,check_neuron};
    wire [32:0] bias_magnitude = bias_data[31] ?
        -{1'b1,bias_data} : {1'b0,bias_data};
    wire input_write = state == INPUT_BYTES;
    assign busy = engine_busy || start_engine;
    assign model_valid = committed;
    assign result_valid = ready_result || engine_done;

    packed_ram #(.AW(11)) weight_ram(clk, engine_weight_rd, engine_weight_addr,
        weight_data, weight_offset[13:3],
        weight_write ? 8'b1 << weight_offset[2:0] : 8'b0, {8{octet}});
    packed_ram #(.AW(10), .BYTES(4)) bias_ram(clk, engine_bias_rd || state==BIAS_READ,
        validating_bias ? check_bias_addr : engine_bias_addr, bias_data, bias_offset[11:2],
        bias_write ? 4'b1 << bias_offset[1:0] : 4'b0, {4{octet}});
    dense_engine #(LANES) engine(clk, rst, start_engine,
        layer_total[2:0], engine_layer, desc[40:32], desc[56:48], desc[165:160], desc[77:67],
        desc[107:98], quant[30:0], quant[36:32], engine_weight_rd, engine_weight_addr,
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
            commit_ok <= 0;
            state <= COMMIT_REPLY;
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
            image_layout_valid <= 0;
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
                            image_layout_valid <= 0;
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
                    // All layout fields have arrived before byte 28. Form the
                    // section ends while consuming the four reserved bytes.
                    if (image_pos == 28) begin
                        desc_end <= 15'd32 + desc_bytes[14:0];
                        image_layout_valid <= sane_layout;
                    end
                    if (image_pos == 29) weight_end <= desc_end + weight_bytes[14:0];
                    if (image_pos == 30) bias_end <= weight_end + bias_bytes[14:0];
                    if (image_pos >= 32 && image_layout_valid) begin
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
                    if (!image_layout_valid || header[31:0] != 32'h3155504e ||
                        header[47:32] != 16'h0001 || header[63:56] != 0 ||
                        header[255:224] != 0 || first_input < 1 || first_input > 256 ||
                        final_output < 1 || final_output > 256 ||
                        bias_end+quant_bytes[14:0] != image_len) reject_model();
                    else begin
                        checked_weights <= 0;
                        checked_biases <= 0;
                        check_layer <= 0;
                        state <= DESC_FETCH;
                    end
                end
                DESC_FETCH: begin
                    check_desc <= descriptors[check_layer];
                    check_quant <= quants[check_layer];
                    check_expected_input <= check_layer == 0 ? first_input :
                        descriptors[prior_layer][63:48];
                    check_final <= {1'b0,check_layer}+3'd1 == layer_total;
                    state <= DESC_PREP;
                end
                DESC_PREP: begin
                    check_weight_span <= check_out[8:0] * check_stride[5:0];
                    next_biases <= {1'b0,checked_biases} + {3'd0,check_out[8:0],2'b0};
                    // INT32_MAX - (input_dim << 14).
                    bias_limit <= {1'b0,(17'd131071 - {8'd0,check_in[8:0]}),14'h3fff};
                    state <= DESC_LIMITS;
                end
                DESC_LIMITS: begin
                    next_weights <= {3'd0,checked_weights} + {check_weight_span,3'b0};
                    state <= CHECK_DESC;
                end
                CHECK_DESC: if (!valid_desc) reject_model();
                else begin
                    check_neuron <= 0;
                    checked_weights <= next_weights[14:0];
                    checked_biases <= next_biases[12:0];
                    state <= BIAS_READ;
                end
                BIAS_READ: state <= BIAS_EVAL;
                BIAS_EVAL: begin
                    bias_in_range <= bias_magnitude <= {1'b0,bias_limit};
                    state <= CHECK_BIAS;
                end
                CHECK_BIAS: if (!bias_in_range) reject_model();
                else if (check_neuron+9'd1 < check_out[8:0]) begin
                    check_neuron <= check_neuron+1;
                    state <= BIAS_READ;
                end else if (check_final) begin
                    commit_ok <= 1;
                    state <= COMMIT_REPLY;
                end else begin
                    check_layer <= check_layer+1;
                    state <= DESC_FETCH;
                end
                COMMIT_REPLY: begin
                    committed <= commit_ok;
                    loading <= 0;
                    model_error <= !commit_ok;
                    send_status(commit_ok ? OK : MODEL_INVALID);
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
