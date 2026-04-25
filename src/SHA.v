module sha (
    input wire clk,
    input wire rst_n,

    // DATA BUS
    input  wire [7:0] data_in,
    output wire       ready_in,
    input  wire       valid_in,
    output wire [7:0] data_out,
    input  wire       data_ready,
    output wire       data_valid,

    // ACK BUS
    input  wire       ack_ready,
    output wire       ack_valid,
    output wire [1:0] module_source_id,

    // TRANSACTION BUS
    input wire [ 1:0] opcode,
    input wire [ 1:0] source_id,
    input wire [ 1:0] dest_id,
    input wire        encdec,     // unused for SHA
    input wire [23:0] addr        // unused
);


  localparam [1:0] OP_LOAD_KEY = 2'b00;  // unused
  localparam [1:0] OP_LOAD_TEXT = 2'b01;
  localparam [1:0] OP_WRITE_RESULT = 2'b10;
  localparam [1:0] OP_HASH = 2'b11;

  // FSM states for top-level wrapper
  localparam IDLE = 3'd0, RD_TEXT = 3'd2, HASH_OP = 3'd3, TX_RES = 3'd4, ACK_HOLD = 3'd5;

  reg [2:0] cState;  // current top-level FSM state
  reg [5:0] byte_cnt;  // used for RD_TEXT and TX_RES

  localparam [1:0] MEM_ID = 2'b00, SHA_ID = 2'b01;

  // ------------------------------------------------------------------------
  // 32-byte fixed message buffer
  // ------------------------------------------------------------------------
  wire         msg_in_ready;
  reg          msg_in_valid;
  reg  [  7:0] msg_in_data;
  reg          msg_in_last;

  wire         msg_valid;
  reg          msg_ready;
  wire [255:0] msg_block;

  msg_buffer_256b msg_buf (
      .clk      (clk),
      .rst_n    (rst_n),
      .byte_cnt (byte_cnt),
      .in_valid (msg_in_valid),
      .in_ready (msg_in_ready),
      .in_data  (msg_in_data),
      .in_last  (msg_in_last),
      .msg_valid(msg_valid),
      .msg_ready(msg_ready),
      .msg_block(msg_block)
  );

  // ------------------------------------------------------------------------
  // SHA-256 core pieces: round constants, message schedule, round unit
  // ------------------------------------------------------------------------
  // Round index
  reg  [ 5:0] t_reg;
  wire [ 5:0] t = t_reg;

  wire [31:0] K_t;

  round_constants rc (
      .idx(t),
      .K_t(K_t)
  );

  // Message schedule: takes the 8 words directly (no 512-bit block)
  // W_t and W_valid are now combinational in message_schedule,
  // driven directly from t_reg so they align with K_t.
  reg         ms_init;
  reg         ms_shift;
  wire [31:0] W_t;
  wire        W_valid;

  message_schedule ms (
      .clk      (clk),
      .rst_n    (rst_n),
      .init     (ms_init),
      .shift    (ms_shift),
      .t        (t),         // undelayed — W_t is now combinational
      .msg_block(msg_block),
      .W_t      (W_t),
      .valid    (W_valid)
  );

  // Working variables a..h
  reg [31:0] a_r, b_r, c_r, d_r, e_r, f_r, g_r, h_r;
  wire [31:0] a_next, b_next, c_next, d_next, e_next, f_next, g_next, h_next;

  // Round handshakes
  reg  round_in_valid;
  wire round_in_ready;
  wire round_out_valid;
  wire round_out_ready;

  assign round_out_ready = 1'b1;  // always ready to consume

  round rnd (
      .clk  (clk),
      .rst_n(rst_n),

      .a_i(a_r),
      .b_i(b_r),
      .c_i(c_r),
      .d_i(d_r),
      .e_i(e_r),
      .f_i(f_r),
      .g_i(g_r),
      .h_i(h_r),
      .K_t(K_t),
      .W_t(W_t),

      .in_valid(round_in_valid),
      .in_ready(round_in_ready),

      .a_o      (a_next),
      .b_o      (b_next),
      .c_o      (c_next),
      .d_o      (d_next),
      .e_o      (e_next),
      .f_o      (f_next),
      .g_o      (g_next),
      .h_o      (h_next),
      .out_valid(round_out_valid),
      .out_ready(round_out_ready)
  );

  // Internal digest
  reg [255:0] digest;
  reg         digest_ready;

  // SHA internal FSM (within HASH_OP)
  localparam SHA_IDLE = 3'd0, 
             SHA_LOAD = 3'd1, 
             SHA_WAIT = 3'd2,  // <-- new
             SHA_ROUND = 3'd3, 
             SHA_DONE = 3'd4;

  reg [2:0] sha_state;

  // ------------------------------------------------------------------------
  // Outputs to external bus
  // ------------------------------------------------------------------------
  assign ready_in         = (cState == RD_TEXT) && msg_in_ready;
  assign ack_valid        = (cState == ACK_HOLD);
  assign module_source_id = SHA_ID;

  reg [7:0] byte_out;
  reg       byte_valid;

  assign data_out   = byte_out;
  assign data_valid = byte_valid;

  // ------------------------------------------------------------------------
  // Top-level FSM + SHA FSM
  // ------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cState         <= IDLE;
      byte_cnt       <= 6'd0;

      msg_in_valid   <= 1'b0;
      msg_in_data    <= 8'd0;
      msg_in_last    <= 1'b0;
      msg_ready      <= 1'b0;

      ms_init        <= 1'b0;
      ms_shift       <= 1'b0;
      round_in_valid <= 1'b0;
      t_reg          <= 6'd0;

      a_r            <= 32'd0;
      b_r            <= 32'd0;
      c_r            <= 32'd0;
      d_r            <= 32'd0;
      e_r            <= 32'd0;
      f_r            <= 32'd0;
      g_r            <= 32'd0;
      h_r            <= 32'd0;

      digest         <= 256'd0;
      digest_ready   <= 1'b0;
      sha_state      <= SHA_IDLE;

      byte_out       <= 8'd0;
      byte_valid     <= 1'b0;
    end else begin
      // defaults
      msg_in_valid   <= 1'b0;
      msg_in_last    <= 1'b0;
      msg_ready      <= 1'b0;
      ms_init        <= 1'b0;
      ms_shift       <= 1'b0;
      round_in_valid <= 1'b0;
      byte_valid     <= 1'b0;
      digest_ready   <= digest_ready;  // sticky until used

      case (cState)
        // ----------------------------------------------------------
        // IDLE: accept commands (load text, hash, write result)
        // ----------------------------------------------------------
        IDLE: begin
          byte_cnt <= 6'd0;

          // Start hash only if we have a loaded message
          if (dest_id == SHA_ID && opcode == OP_HASH) begin
            if (msg_valid && !digest_ready) begin
              // Init SHA internal state
              t_reg        <= 6'd0;
              a_r          <= 32'h6a09e667;
              b_r          <= 32'hbb67ae85;
              c_r          <= 32'h3c6ef372;
              d_r          <= 32'ha54ff53a;
              e_r          <= 32'h510e527f;
              f_r          <= 32'h9b05688c;
              g_r          <= 32'h1f83d9ab;
              h_r          <= 32'h5be0cd19;

              sha_state    <= SHA_LOAD;
              digest_ready <= 1'b0;
              cState       <= HASH_OP;
            end
          end  // Load message (32 bytes)
          else if (source_id == MEM_ID && dest_id == SHA_ID &&
                             opcode == OP_LOAD_TEXT && !msg_valid) begin
            cState   <= RD_TEXT;
            byte_cnt <= 6'd0;
          end  // Write result (only if digest ready)
          else if (opcode  == OP_WRITE_RESULT &&
                             source_id== SHA_ID &&
                             dest_id  == MEM_ID &&
                             digest_ready) begin
            cState   <= TX_RES;
            byte_cnt <= 6'd0;
          end
        end

        // ----------------------------------------------------------
        // RD_TEXT: read 32-byte message and feed msg_buffer_256b
        // ----------------------------------------------------------
        RD_TEXT: begin
          if (valid_in && ready_in) begin
            msg_in_valid <= 1'b1;
            msg_in_data  <= data_in;

            // Mark last byte (32nd) for buffer
            if (byte_cnt == 6'd31) msg_in_last <= 1'b1;

            byte_cnt <= byte_cnt + 1'b1;

            if (byte_cnt == 6'd31) begin
              // 32nd byte just accepted; msg_buffer will assert msg_valid
              cState <= IDLE;
            end
          end
        end

        // ----------------------------------------------------------
        // HASH_OP: run SHA internal FSM until digest_ready
        // ----------------------------------------------------------
        HASH_OP: begin
          // SHA engine sub-FSM
          case (sha_state)
            SHA_IDLE: begin
              // should not stay here; handled from IDLE
              sha_state <= SHA_LOAD;
            end

            // Pulse ms_init once, then wait for W_valid and start round 0
            SHA_LOAD: begin
                ms_init   <= 1'b1;
                sha_state <= SHA_WAIT;  // cycle N: init pulses, window loads
            end

            SHA_WAIT: begin
                sha_state <= SHA_ROUND; // cycle N+1: W_t_next valid, wait one more
            end                         // cycle N+2: W_t registered output is ready

            SHA_ROUND: begin
              // start round when W_t valid and round ready
              if (W_valid && round_in_ready && !round_out_valid) begin
                round_in_valid <= 1'b1;
              end

              // Consume round result
              if (round_out_valid) begin
                a_r <= a_next;
                b_r <= b_next;
                c_r <= c_next;
                d_r <= d_next;
                e_r <= e_next;
                f_r <= f_next;
                g_r <= g_next;
                h_r <= h_next;

                if (t_reg < 6'd63) begin
                  // setup next round
                  if (t_reg >= 6'd15 && t_reg < 6'd63) ms_shift <= 1'b1;

                  t_reg <= t_reg + 6'd1;
                end else begin
                  // finished t = 63
                  sha_state <= SHA_DONE;
                end
              end
            end

            SHA_DONE: begin
              // Finalize digest = IV + working vars
              digest[255:224] <= 32'h6a09e667 + a_r;
              digest[223:192] <= 32'hbb67ae85 + b_r;
              digest[191:160] <= 32'h3c6ef372 + c_r;
              digest[159:128] <= 32'ha54ff53a + d_r;
              digest[127:96]  <= 32'h510e527f + e_r;
              digest[95:64]   <= 32'h9b05688c + f_r;
              digest[63:32]   <= 32'h1f83d9ab + g_r;
              digest[31:0]    <= 32'h5be0cd19 + h_r;

              digest_ready    <= 1'b1;
              sha_state       <= SHA_IDLE;
              cState          <= IDLE;

              // tell msg_buffer we’re done with the current message
              msg_ready       <= 1'b1;
            end
            default: sha_state <= SHA_IDLE;
          endcase
        end

        // ----------------------------------------------------------
        // TX_RES: stream 32-byte digest out, MSB-first
        // ----------------------------------------------------------
        TX_RES: begin
          if (data_ready) begin
            byte_valid <= 1'b1;
            byte_out   <= digest[255-byte_cnt*8-:8];
            byte_cnt   <= byte_cnt + 1'b1;

            if (byte_cnt == 6'd31) begin
              cState <= ACK_HOLD;
            end
          end
        end

        // ----------------------------------------------------------
        // ACK_HOLD: wait for ack, then return to IDLE
        // ----------------------------------------------------------
        ACK_HOLD: begin
          if (ack_ready) begin
            digest_ready <= 1'b0;
            cState       <= IDLE;
          end
        end

        default: cState <= IDLE;
      endcase
    end
  end

  // Mark unused inputs so synthesis doesn't complain
  wire _unused = &{addr, encdec, OP_LOAD_KEY};

endmodule