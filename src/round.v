module round(
  input  wire         clk,
  input  wire         rst_n,

  input  wire [31:0]  a_i, b_i, c_i, d_i, e_i, f_i, g_i, h_i,
  input  wire [31:0]  K_t,
  input  wire [31:0]  W_t,
  input  wire         in_valid,
  output reg          in_ready,

  output reg  [31:0]  a_o, b_o, c_o, d_o, e_o, f_o, g_o, h_o,
  output reg          out_valid,
  input  wire         out_ready
);

  localparam IDLE = 1'b0;
  localparam COMP = 1'b1;
  reg phase;

  function automatic [31:0] Ch(input [31:0] x, input [31:0] y, input [31:0] z);
    Ch = (x & y) ^ (~x & z);
  endfunction

  function automatic [31:0] Ma(input [31:0] x, input [31:0] y, input [31:0] z);
    Ma = (x & y) ^ (x & z) ^ (y & z);
  endfunction

  function automatic [31:0] ROTR(input [31:0] x, input integer n);
    ROTR = (x >> n) | (x << (32-n));
  endfunction

  function automatic [31:0] S0(input [31:0] x);
    S0 = ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22);
  endfunction

  function automatic [31:0] S1(input [31:0] x);
    S1 = ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25);
  endfunction

  // --- shared subexpressions (one instance each) ---
  wire [31:0] ch_e   = Ch(e_i, f_i, g_i);
  wire [31:0] maj_a  = Ma(a_i, b_i, c_i);
  wire [31:0] s0_a   = S0(a_i);
  wire [31:0] s1_e   = S1(e_i);

  wire [31:0] T1     = h_i + s1_e + ch_e + K_t + W_t;
  wire [31:0] T2     = s0_a + maj_a;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid <= 1'b0;
      in_ready  <= 1'b0;
      phase     <= IDLE;
    end else begin
      case (phase)
        IDLE: begin
          in_ready  <= 1'b1;
          out_valid <= 1'b0;
          if (in_valid && out_ready) begin
            phase <= COMP;
          end
        end

        COMP: begin
          in_ready  <= 1'b0;

          a_o <= T1 + T2;
          b_o <= a_i;
          c_o <= b_i;
          d_o <= c_i;
          e_o <= d_i + T1;
          f_o <= e_i;
          g_o <= f_i;
          h_o <= g_i;

          out_valid <= 1'b1;
          if (out_ready)
            phase <= IDLE;
        end
      endcase
    end
  end
endmodule
