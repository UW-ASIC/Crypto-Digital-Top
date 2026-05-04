//////////////////////////////////////////////////////////////////////////////////
//Mix Columns Module
//By: Ada M
//LUT:192
//FF:0
//DSP:0
//BRAM:0
//
//////////////////////////////////////////////////////////////////////////////////


module mixcolumns(
    input [127:0] state_in,
    input final_round,
    output [127:0] state_out
    );
    
    function automatic [7:0] mul2 (input [7:0] b);
        mul2 = {b[6:0],1'b0} ^ (8'h1B & {8{b[7]}});
    endfunction

    function automatic [7:0] mul3 (input [7:0] b);
        mul3 = mul2(b) ^ b;
    endfunction
    
    
    
wire [7:0] s [0:15];
genvar i;
generate for (i=0;i<16;i=i+1) begin
  assign s[i] = state_in[127-8*i -: 8];
end endgenerate

// mix one column
function automatic [31:0] mix_col(input [7:0] a0,a1,a2,a3);
  reg [7:0] b0,b1,b2,b3;
  begin
    b0 = mul2(a0) ^ mul3(a1) ^ a2      ^ a3;
    b1 = a0      ^ mul2(a1) ^ mul3(a2) ^ a3;
    b2 = a0      ^ a1       ^ mul2(a2) ^ mul3(a3);
    b3 = mul3(a0)^ a1       ^ a2       ^ mul2(a3);
    mix_col = {b0,b1,b2,b3};
  end
endfunction

// compute the 4 columns (parallel)
wire [31:0] col0 = mix_col(s[0], s[1], s[2], s[3]);
wire [31:0] col1 = mix_col(s[4], s[5], s[6], s[7]);
wire [31:0] col2 = mix_col(s[8], s[9], s[10], s[11]);
wire [31:0] col3 = mix_col(s[12], s[13], s[14], s[15]);

// pack them back - ALL AT ONCE
wire [127:0] mixed = {col0, col1, col2, col3}; 

assign state_out = final_round ? state_in : mixed;
    
endmodule