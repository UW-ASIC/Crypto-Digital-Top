module message_schedule(
  input  wire         clk,
  input  wire         rst_n,

  // Control
  input  wire         init,     // Pulse to load W[0..15] from block
  input  wire         shift,    // For t>=16: compute next W and slide window
  input  wire [5:0]   t,        // Current round index (0..63) — undelayed t_reg

  // Data
  input  wire [255:0] msg_block,  // 8x32-bit message, big-endian
  output wire [31:0]  W_t,      // Word for current round t (combinational)
  output wire         valid     // High when W_t is meaningful (after init)
);

  // 16-word sliding window
  reg [31:0] W_window [0:15];

  // Flag that we've done init and window holds valid data
  reg initialized;

  integer i;

  // --------------------------------------------------------
  // sigma0, sigma1 for message schedule expansion
  // --------------------------------------------------------

    function automatic [31:0] rotr(input [31:0] x, input integer n);
    rotr = (x >> n) | (x << (32-n));
    endfunction

    function automatic [31:0] sigma0(input [31:0] x);
    sigma0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
    endfunction

    function automatic [31:0] sigma1(input [31:0] x);
    sigma1 = rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
    endfunction

    wire [31:0] s0 = sigma0(W_window[1]);
    wire [31:0] s1 = sigma1(W_window[14]);

  // Next word to append at tail
  wire [31:0] W_next = s1 + W_window[9] + s0 + W_window[0];

  // --------------------------------------------------------
  // Combinational outputs — W_t and valid are wires so they
  // track t_reg on the same cycle as K_t (also combinational).
  // This eliminates the pipeline skew that caused W[t-1] to
  // be paired with K[t].
  // --------------------------------------------------------

  reg  [3:0]  read_idx;
  reg  [31:0] W_t_comb;
  reg         valid_comb;

  always @(*) begin
    if (!initialized) begin
      read_idx   = 4'd0;
      W_t_comb   = 32'b0;
      valid_comb = 1'b0;
    end else begin
      if (t < 16)
        read_idx = t[3:0];
      else
        read_idx = 4'd15;

      // Write-through bypass: when a shift is happening on this same
      // cycle and we would read W_window[15], use the freshly-computed
      // W_next instead.  This is needed because the round module's
      // COMP phase can overlap with the window shift — the round would
      // otherwise see the stale (pre-shift) value at position 15.
      if (shift && initialized && (t >= 6'd16))
        W_t_comb = W_next;
      else
        W_t_comb = W_window[read_idx];

      valid_comb = 1'b1;
    end
  end

  assign W_t  = W_t_comb;
  assign valid = valid_comb;

  // --------------------------------------------------------
  // Sequential: load window on init, slide on shift.
  //
  // t is now undelayed t_reg.  When SHA.v sets ms_shift on
  // the same edge that t_reg increments from N to N+1,
  // message_schedule sees t=N+1 on the next posedge.
  // Shift condition adjusted accordingly: (t >= 16) && (t <= 63).
  // --------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      initialized <= 1'b0;
      for (i = 0; i < 16; i = i + 1)
        W_window[i] <= 32'b0;

    end else begin
      if (init) begin
        // W[0..7] from 256-bit message block
        W_window[0] <= msg_block[255:224];
        W_window[1] <= msg_block[223:192];
        W_window[2] <= msg_block[191:160];
        W_window[3] <= msg_block[159:128];
        W_window[4] <= msg_block[127:96];
        W_window[5] <= msg_block[95:64];
        W_window[6] <= msg_block[63:32];
        W_window[7] <= msg_block[31:0];

        // Fixed SHA-256 padding for a 256-bit (32-byte) message
        W_window[8]  <= 32'h8000_0000;
        W_window[9]  <= 32'h0000_0000;
        W_window[10] <= 32'h0000_0000;
        W_window[11] <= 32'h0000_0000;
        W_window[12] <= 32'h0000_0000;
        W_window[13] <= 32'h0000_0000;
        W_window[14] <= 32'h0000_0000;
        W_window[15] <= 32'h0000_0100; // length = 256 bits

        initialized <= 1'b1;

      end else if (initialized && shift && (t >= 6'd16)) begin
        // Slide window left, append W_next at tail
        for (i = 0; i < 15; i = i + 1)
          W_window[i] <= W_window[i+1];
        W_window[15] <= W_next;
      end
    end
  end

endmodule