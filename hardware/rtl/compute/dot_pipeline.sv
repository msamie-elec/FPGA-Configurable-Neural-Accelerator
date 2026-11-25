// Fixed-latency pipeline. Bubbles advance with their valid bits.
module dot_pipeline #(parameter integer LANES=4)(
    input wire clk, rst, valid, last,
    input wire [LANES*8-1:0] a, w,
    input wire [LANES-1:0] mask,
    output wire out_valid, out_last,
    output wire signed [18:0] sum
);
    localparam integer LEVELS = $clog2(LANES);
    reg [LEVELS:0] vpipe, lpipe;
    always @(posedge clk) begin
        if (rst) begin
            vpipe[0] <= 0;
            lpipe[0] <= 0;
        end else begin
            vpipe[0] <= valid;
            lpipe[0] <= last;
        end
    end
    wire signed [18:0] tree [0:LEVELS][0:LANES-1];
    genvar i, l, j;
    generate
        for (i=0; i<LANES; i=i+1) begin : pe
            wire signed [7:0] x = a[i*8+:8];
            wire signed [7:0] y = w[i*8+:8];
            reg signed [15:0] product;
            always @(posedge clk) if (valid) product <= mask[i] ? x*y : 16'sd0;
            assign tree[0][i] = {{3{product[15]}},product};
        end
        for (l=1; l<=LEVELS; l=l+1) begin : reduction
            always @(posedge clk) begin
                if (rst) begin
                    vpipe[l] <= 0;
                    lpipe[l] <= 0;
                end else begin
                    vpipe[l] <= vpipe[l-1];
                    lpipe[l] <= lpipe[l-1];
                end
            end
            for (j=0; j<(LANES>>l); j=j+1) begin : pair
                reg signed [18:0] accum;
                always @(posedge clk)
                    if (vpipe[l-1]) accum <= tree[l-1][2*j] + tree[l-1][2*j+1];
                assign tree[l][j] = accum;
            end
        end
    endgenerate
    assign out_valid = vpipe[LEVELS];
    assign out_last = lpipe[LEVELS];
    assign sum = tree[LEVELS][0];
endmodule
