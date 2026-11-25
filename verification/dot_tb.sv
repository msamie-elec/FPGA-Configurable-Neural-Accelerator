module dot_tb;
    parameter integer LANES=4;
    localparam integer LAT=$clog2(LANES)+1;
    reg clk=0, rst=1, valid=0, last=0;
    reg [LANES*8-1:0] a=0, w=0;
    reg [LANES-1:0] mask=0;
    wire out_valid, out_last;
    wire signed [18:0] sum;
    integer expected [0:LAT-1];
    reg [LAT-1:0] valid_q=0, last_q=0;
    integer x,y,i,k,j,ref_sum;
    integer checked=0;
    always #5 clk=~clk;
    dot_pipeline #(LANES) dut(clk,rst,valid,last,a,w,mask,out_valid,out_last,sum);

    // Compare pre-edge registered outputs to the scalar model, then queue this edge.
    always @(posedge clk) begin
        if (rst) begin
            valid_q=0;
            last_q=0;
        end else begin
            if (out_valid !== valid_q[LAT-1]) $fatal(1,"Unexpected pipeline validity");
            if (out_valid) begin
                if ($signed(sum) !== expected[LAT-1] || out_last !== last_q[LAT-1])
                    $fatal(1,"Dot result/tag mismatch at case %0d",checked);
                checked=checked+1;
            end
            ref_sum=0;
            for (j=0;j<LANES;j=j+1)
                if (mask[j]) ref_sum=ref_sum + $signed(a[j*8+:8])*$signed(w[j*8+:8]);
            for (k=LAT-1;k>0;k=k-1) expected[k]=expected[k-1];
            expected[0]=ref_sum;
            valid_q=(valid_q<<1)|valid;
            last_q=(last_q<<1)|last;
        end
    end
    initial begin
        repeat (2) @(negedge clk);
        rst=0;
        for (x=-128;x<=127;x=x+1) begin
            for (y=-128;y<=127;y=y+1) begin
                valid=1;
                last=(y==127);
                for (i=0;i<LANES;i=i+1) begin
                    a[i*8+:8]=8'(x);
                    w[i*8+:8]=8'(y);
                    mask[i]=(i==0) || (x==-128 && y==-128) || (((x+y+i)&3)!=0);
                end
                @(negedge clk);
            end
            valid=0;
            @(negedge clk);
        end
        repeat (LAT+1) @(negedge clk);
        if (checked != 65536) $fatal(1,"Expected all INT8 operand pairs");
        $display("PASS P=%0d: %0d pipeline outputs, last tags, and injected bubbles",LANES,checked);
        $finish;
    end
endmodule
