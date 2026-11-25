// Synchronous read, independent byte write enables. No RAM reset.
module packed_ram #(
    parameter integer AW = 5,
    parameter integer BYTES = 8
)(
    input wire clk,
    input wire rd_en,
    input wire [AW-1:0] rd_addr,
    output reg [BYTES*8-1:0] rd_data,
    input wire [AW-1:0] wr_addr,
    input wire [BYTES-1:0] wr_en,
    input wire [BYTES*8-1:0] wr_data
);
    genvar b;
    generate for (b = 0; b < BYTES; b = b + 1) begin : lane
        reg [7:0] mem [0:(1<<AW)-1];
        always @(posedge clk) begin
            if (wr_en[b]) mem[wr_addr] <= wr_data[b*8+:8];
            if (rd_en) rd_data[b*8+:8] <= mem[rd_addr];
        end
    end endgenerate
endmodule
