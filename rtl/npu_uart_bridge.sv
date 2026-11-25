// Framed serial bridge to eight-lane scalable NPU.
// Request: A5 CMD PAYLOAD XOR(CMD,PAYLOAD). Fixed payload lengths:
// W 0x57: address_lo,address_hi,value (3)
// B 0x42: address, signed bias LE32 (5)
// C 0x43: layer_count,input_size,size0,size1,size2,size3,shift (7)
// I 0x49: 32 signed INT8 input bytes (32)
// P 0x50: empty payload (0)
// Response: 5A CMD STATUS CLASS OUTPUT[0:7] XOR(CMD,STATUS,CLASS,OUTPUTS).
// STATUS: 0=ok,1=checksum,2=bad_command,3=NPU_error.
// Transaction-oriented: sender MUST await response before next request.
// No host packets while computation/response is underway.
module npu_uart_bridge #(
  parameter integer CLOCK_HZ=100000000,
  parameter integer BAUD=115200
)(
  input wire clk,rst,serial_rx,
  output wire serial_tx,
  output wire npu_busy,
  output reg [2:0] last_class,
  output reg result_seen
);
  wire [7:0] rx_data;
  wire rx_valid,tx_busy;
  reg tx_start=0;
  reg [7:0] tx_data=0;
  uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) u_rx(
    .clk(clk),.rst(rst),.rx(serial_rx),.data(rx_data),.valid(rx_valid)
  );
  uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) u_tx(
    .clk(clk),.rst(rst),.start(tx_start),.data(tx_data),.tx(serial_tx),.busy(tx_busy)
  );

  reg [2:0] state=0;
  localparam RX=0, WAIT_CORE=1, RESP_SEND=2, RESP_BUSY=3, RESP_IDLE=4;
  reg [1:0] parse_state=0;
  reg [7:0] cmd=0, payload[0:31];
  reg [5:0] payload_len=0,offset=0;
  reg [7:0] check_xor=0;
  reg [7:0] response_cmd=0,response_status=0;
  reg [2:0] response_class=0;
  reg [63:0] response_scores=0;
  reg [3:0] send_idx=0;
  reg [7:0] send_byte,send_checksum;
  integer k;
  reg start=0,weight_we=0,bias_we=0;
  reg [11:0] weight_addr=0;
  reg [7:0] weight_data=0;
  reg [6:0] bias_addr=0;
  reg [31:0] bias_data=0;
  reg [2:0] layers=3;
  reg [5:0] ins=4,s0=8,s1=4,s2=2,s3=1;
  reg [3:0] quant_shift=4;
  reg [255:0] features=0;
  wire valid,error;
  wire [2:0] predicted_class;
  wire [63:0] scores;
  npu_scalable_core accelerator(
    .clk(clk),.rst(rst),.start(start),.features(features),
    .layer_count(layers),.input_size(ins),
    .size0(s0),.size1(s1),.size2(s2),.size3(s3),
    .shift(quant_shift),
    .weight_we(weight_we),.weight_addr(weight_addr),.weight_data(weight_data),
    .bias_we(bias_we),.bias_addr(bias_addr),.bias_data(bias_data),
    .busy(npu_busy),.valid(valid),.error(error),
    .predicted_class(predicted_class),.outputs(scores)
  );
  always @* begin
    send_byte=0;
    case(send_idx)
      0:send_byte=8'h5a;
      1:send_byte=response_cmd;
      2:send_byte=response_status;
      3:send_byte={5'd0,response_class};
      12:send_byte=send_checksum;
      default: if(send_idx>=4 && send_idx<=11)
        send_byte=response_scores[(send_idx-4)*8+:8];
    endcase
    send_checksum=response_cmd ^ response_status ^ {5'd0,response_class};
    for(integer b=0;b<8;b=b+1)
      send_checksum=send_checksum ^ response_scores[b*8+:8];
  end

  always @(posedge clk) begin
    if(rst) begin
      state<=RX;parse_state<=0;payload_len<=0;offset<=0;check_xor<=0;
      response_cmd<=0;response_status<=0;response_class<=0;
      response_scores<=0;send_idx<=0;
      tx_start<=0;tx_data<=0;
      start<=0;weight_we<=0;bias_we<=0;
      last_class<=0;result_seen<=0;
      layers<=3;ins<=4;s0<=8;s1<=4;s2<=2;s3<=1;quant_shift<=4;
      features<=0;
    end else begin
      tx_start<=0;start<=0;weight_we<=0;bias_we<=0;
      case(state)
        RX: if(rx_valid) begin
          case(parse_state)
            0: if(rx_data==8'ha5) parse_state<=1;
            1: begin
              cmd<=rx_data;check_xor<=rx_data;offset<=0;
              case(rx_data)
                8'h57:payload_len<=3;
                8'h42:payload_len<=5;
                8'h43:payload_len<=7;
                8'h49:payload_len<=32;
                8'h50:payload_len<=0;
                default:payload_len<=0;
              endcase
              parse_state<=2;
            end
            2: begin
              if(offset<payload_len) begin
                payload[offset]<=rx_data;
                check_xor<=check_xor^rx_data;
                offset<=offset+1'b1;
              end else begin
                parse_state<=0;
                response_cmd<=cmd;response_status<=0;
                response_class<=0;response_scores<=0;send_idx<=0;
                if(check_xor!=rx_data)
                  response_status<=1;
                else begin
                  case(cmd)
                    8'h57:begin
                      weight_addr<={payload[1][3:0],payload[0]};
                      weight_data<=payload[2];
                      weight_we<=1;
                    end
                    8'h42:begin
                      bias_addr<=payload[0][6:0];
                      bias_data<={payload[4],payload[3],payload[2],payload[1]};
                      bias_we<=1;
                    end
                    8'h43:begin
                      layers<=payload[0][2:0];
                      ins<=payload[1][5:0];
                      s0<=payload[2][5:0];s1<=payload[3][5:0];
                      s2<=payload[4][5:0];s3<=payload[5][5:0];
                      quant_shift<=payload[6][3:0];
                    end
                    8'h49:begin
                      for(k=0;k<32;k=k+1)
                        features[k*8+:8]<=payload[k];
                      start<=1;
                    end
                    8'h50:begin end
                    default:response_status<=2;
                  endcase
                end
                if(cmd==8'h49 && check_xor==rx_data)
                  state<=WAIT_CORE;
                else state<=RESP_SEND;
              end
            end
          endcase
        end
        WAIT_CORE:if(valid) begin
          response_status<=error?8'd3:8'd0;
          response_class<=predicted_class;
          response_scores<=scores;
          last_class<=predicted_class;result_seen<=!error;
          state<=RESP_SEND;
        end
        RESP_SEND:if(!tx_busy) begin
          tx_data<=send_byte;tx_start<=1;state<=RESP_BUSY;
        end
        RESP_BUSY:if(tx_busy) state<=RESP_IDLE;
        RESP_IDLE:if(!tx_busy) begin
          if(send_idx==12) begin send_idx<=0;state<=RX;end
          else begin send_idx<=send_idx+1'b1;state<=RESP_SEND;end
        end
        default:state<=RX;
      endcase
    end
  end
endmodule
