// ============================================================================
// AES-256 core (single shared S-box, bytewise load of key & state)
// ============================================================================
module aes_core_rs (
    input  wire        clk,
    input  wire        rst_n,

    // Bytewise key load (256-bit key, 32 bytes)
    input  wire        ld_key_valid,
    input  wire [7:0]  ld_key_byte,
    output wire        ld_key_ready,

    // Bytewise state load (128-bit state, 16 bytes)
    input  wire        ld_state_valid,
    input  wire [7:0]  ld_state_byte,
    output wire        ld_state_ready,

    // Start encryption once key & state are fully loaded
    input  wire        start,
    output wire  [127:0] state_out,
    output reg         done
);

    // ------------------------------------------------------------------------
    // Internal storage for key & state
    // ------------------------------------------------------------------------
    // reg [127:0] state_load;      // loaded AES state 
    reg [127:0] state_reg;      // current AES state (in-place updated)
    reg [127:0] sb_src_reg;     // snapshot before SubBytes+ShiftRows
    reg [127:0] state_reg_next;
    // goal: collapse state registers where possible.

    reg [4:0]   key_idx;
    reg         key_full;

    reg [3:0]   state_idx;
    reg         state_full;

    // ------------------------------------------------------------------------
    // AES round control
    // ------------------------------------------------------------------------
    reg [3:0]   round;          // 1..14
    reg         final_round;
    reg [2:0]   st;

    localparam S_IDLE = 3'd0;
    localparam S_INIT = 3'd1;
    localparam S_SB   = 3'd2;
    localparam S_MC   = 3'd3;
    localparam S_ARK  = 3'd4;
    localparam S_KS   = 3'd5;
    localparam S_OUT  = 3'd6;

    // ------------------------------------------------------------------------
    // Single shared S-box
    // ------------------------------------------------------------------------
    reg  [7:0] sbox_in;
    wire [7:0] sbox_out;

    sbox u_sbox (
        .byte_in (sbox_in),
        .byte_out(sbox_out)
    );

    // ------------------------------------------------------------------------
    // Streaming SubBytes+ShiftRows engine
    // ------------------------------------------------------------------------
    reg         sb_start;
    wire        sb_done;
    wire        sb_we;
    wire [3:0]  sb_idx;
    wire [7:0]  sb_byte;
    wire [7:0]  sb_sbox_in;

    subbytes u_sb (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (sb_start),
        .state_in (sb_src_reg),
        .done     (sb_done),
        .we       (sb_we),
        .byte_idx (sb_idx),
        .byte_out (sb_byte),
        .sbox_in  (sb_sbox_in),
        .sbox_out (sbox_out)
    );

    // ------------------------------------------------------------------------
    // MixColumns (combinational), final-round aware
    //   - Input is state_reg AFTER SB+ShiftRows
    // ------------------------------------------------------------------------
    wire [127:0] mc_out;

    mixcolumns u_mc (
        .state_in   (state_reg),
        .final_round(final_round),
        .state_out  (mc_out)
    );

    // ------------------------------------------------------------------------
    // Key schedule (roundkeygen_1lane) using same S-box
    // ------------------------------------------------------------------------
    reg [31:0] key_buf [0:7];   // sliding window {wK..wK+7}
    reg [2:0]  rcon_idx;
    reg        use_rcon;

    reg        rk_start;
    wire       rk_done;
    wire [31:0] w8, w9, w10, w11;
    wire [2:0]  rcon_idx_next;
    wire        use_rcon_next;
    wire [7:0]  rk_sbox_in;

    roundkeygen_1lane u_rk (
        .clk         (clk),
        .rst_n       (rst_n),
        .w0          (key_buf[0]),
        .w1          (key_buf[1]),
        .w2          (key_buf[2]),
        .w3          (key_buf[3]),
        .w4          (key_buf[4]),
        .w5          (key_buf[5]),
        .w6          (key_buf[6]),
        .w7          (key_buf[7]),
        .rcon_idx_in (rcon_idx),
        .use_rcon_in (use_rcon),
        .start       (rk_start),
        .w8          (w8),
        .w9          (w9),
        .w10         (w10),
        .w11         (w11),
        .rcon_idx_out(rcon_idx_next),
        .use_rcon_out(use_rcon_next),
        .done        (rk_done),
        .sbox_in     (rk_sbox_in),
        .sbox_out    (sbox_out)
    );

    wire [127:0] curr_rkey = { key_buf[4], key_buf[5],
                            key_buf[6], key_buf[7] };

    reg         rk_started;     // have we pulsed rk_start in this S_KS?

    // ------------------------------------------------------------------------
    // S-box ownership: SubBytes vs KeySchedule
    // ------------------------------------------------------------------------
    always @* begin
        case (st)
            S_SB:  sbox_in = sb_sbox_in;
            S_KS:  sbox_in = rk_sbox_in;
            default: sbox_in = 8'h00;
        endcase
    end

    // ------------------------------------------------------------------------
    // Load handshakes (only in IDLE & !start)
    // ------------------------------------------------------------------------
    assign ld_key_ready = (st == S_IDLE) && !key_full;
    assign ld_state_ready = (st == S_IDLE) && !state_full;

    // ------------------------------------------------------------------------
    // Combinational next-state logic for state_reg
    // ------------------------------------------------------------------------
    always @* begin
        // default: hold current value
        state_reg_next = state_reg;

        // 1) Initial AddRoundKey in S_IDLE when we see start
        if (st == S_IDLE && start && key_full && state_full) begin
            state_reg_next = state_reg ^ { key_buf[0], key_buf[1],
                                            key_buf[2], key_buf[3] };
        end

        // 2) SubBytes/ShiftRows byte write in S_SB (overwrites one byte)
        if (st == S_SB && sb_we) begin
            // update only the selected byte, keep others
            state_reg_next[127 - sb_idx*8 -: 8] = sb_byte;
        end

        // 3) AddRoundKey after MixColumns in S_ARK (overwrites entire state)
        // if (st == S_ARK) begin
        //     state_reg_next = mc_out ^ curr_rkey;
        // end
    end

    integer i;

    // ------------------------------------------------------------------------
    // Main sequential logic
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // global
            st          <= S_IDLE;
            round       <= 4'd0;
            final_round <= 1'b0;
            done        <= 1'b0;
            // state_out   <= 128'd0;

            // state/key storage
            key_idx     <= 5'd0;
            key_full    <= 1'b0;

            // state_load  <= 128'd0;
            state_reg   <= 128'd0;
            sb_src_reg  <= 128'd0;
            state_idx   <= 4'd0;
            state_full  <= 1'b0;

            // key schedule
            for (i = 0; i < 8; i = i + 1)
                key_buf[i] <= 32'd0;
            rcon_idx   <= 3'd0;
            use_rcon   <= 1'b1;
            rk_start   <= 1'b0;
            rk_started <= 1'b0;

            // SubBytes control
            sb_start   <= 1'b0;

        end else begin
            // defaults each cycle
            sb_start  <= 1'b0;
            rk_start  <= 1'b0;

            // --------------------------------------------------------------
            // Load key/state in IDLE (before start)
            // --------------------------------------------------------------
            if (st == S_IDLE && !start) begin
                // Key load (MSB-first)
                if (ld_key_valid && ld_key_ready) begin
                    case (key_idx[1:0])
                        2'd0: key_buf[key_idx[4:2]][31:24] <= ld_key_byte;
                        2'd1: key_buf[key_idx[4:2]][23:16] <= ld_key_byte;
                        2'd2: key_buf[key_idx[4:2]][15:8]  <= ld_key_byte;
                        2'd3: key_buf[key_idx[4:2]][7:0]   <= ld_key_byte;
                    endcase

                    if (key_idx == 5'd31) begin
                        key_full <= 1'b1;
                    end else begin
                        key_idx <= key_idx + 5'd1;
                    end
                end

                // Shift-register style state load (MSB-first overall)
                if (ld_state_valid && ld_state_ready) begin
                    // shift left by 8 bits, insert new byte at LSB
                    state_reg <= { state_reg[119:0], ld_state_byte };

                    if (state_idx == 4'd15) begin
                        state_full <= 1'b1;
                    end else begin
                        state_idx <= state_idx + 4'd1;
                    end
                end
            end else begin
                state_reg <= state_reg_next;
            end
            // --------------------------------------------------------------
            // AES control FSM
            // --------------------------------------------------------------
            case (st)
                // ----------------------------------------------------------
                // IDLE: wait for start, require key & state fully loaded
                // ----------------------------------------------------------
                S_IDLE: begin
                    if (start && key_full && state_full) begin
                        // key_buf[0..7] already hold w0..w7

                        // Initial AddRoundKey with K0 = {w0..w3}
                        //state_reg <= state_load ^ { key_buf[0], key_buf[1],
                          //                      key_buf[2], key_buf[3] };

                        // Key schedule state
                        rcon_idx   <= 3'd0;
                        use_rcon   <= 1'b1;

                        // Round counter
                        round       <= 4'd1;
                        final_round <= 1'b0;

                        rk_started <= 1'b0;

                        // next we’ll snapshot state and start SB+SR
                        st <= S_INIT;
                    end
                    done <= 0;
                end
                // ----------------------------------------------------------
                // INIT: snapshot state_reg and start SB+SR
                // ----------------------------------------------------------
                S_INIT: begin
                    sb_src_reg <= state_reg;  // snapshot pre-round state
                    sb_start   <= 1'b1;
                    st         <= S_SB;
                end

                // ----------------------------------------------------------
                // SB: streaming SB+SR updates state_reg via sb_we/sb_idx/sb_byte
                // ----------------------------------------------------------
                S_SB: begin
                    //if (sb_we) begin
                      //  state_reg[127 - 8*sb_idx -: 8] <= sb_byte;
                    //end
                    if (sb_done) begin
                        st <= S_MC;
                    end
                end

                // ----------------------------------------------------------
                // MC: set final_round flag, ready for ARK
                // ----------------------------------------------------------
                S_MC: begin
                    final_round <= (round == 4'd14);
                    st          <= S_ARK;
                end

                // ----------------------------------------------------------
                // ARK: AddRoundKey; if last round, finish; else key schedule
                // ----------------------------------------------------------
                S_ARK: begin
                    state_reg <= mc_out ^ curr_rkey;
                    if (round == 4'd14) begin
                        // state_out <= mc_out ^ curr_rkey;
                        done      <= 1'b1;
                        st        <= S_OUT;
                    end else begin
                        rk_started<= 1'b0;
                        st        <= S_KS;
                    end
                end
                // ----------------------------------------------------------
                // KS: compute next round key K_{round+1}
                // ----------------------------------------------------------
                S_KS: begin
                    if (!rk_started) begin
                        rk_start   <= 1'b1;   // 1-cycle pulse
                        rk_started <= 1'b1;
                    end

                    if (rk_done) begin
                        // slide window {wK..wK+7} -> {wK+4..wK+11}
                        key_buf[0] <= key_buf[4];
                        key_buf[1] <= key_buf[5];
                        key_buf[2] <= key_buf[6];
                        key_buf[3] <= key_buf[7];
                        key_buf[4] <= w8;
                        key_buf[5] <= w9;
                        key_buf[6] <= w10;
                        key_buf[7] <= w11;

                        rcon_idx <= rcon_idx_next;
                        use_rcon <= use_rcon_next;

                        round <= round + 4'd1;

                        // next round: snapshot & start SB again
                        st <= S_INIT;
                    end
                end

                // ----------------------------------------------------------
                // OUT: ciphertext in state_out, clear state loader
                // ----------------------------------------------------------
                S_OUT: begin
                    state_idx  <= 4'd0;
                    key_idx  <= 5'd0;
                    state_full <= 1'b0;
                    key_full   <= 1'b0;
                    st         <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end

assign state_out = state_reg;

endmodule