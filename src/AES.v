module aes (
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
    output wire [1:0] module_source_id
);


    // Opcodes 
    localparam [1:0] OP_LOAD_KEY    = 2'b00;
    localparam [1:0] OP_LOAD_TEXT   = 2'b01;
    localparam [1:0] OP_WRITE_RESULT= 2'b10;
    localparam [1:0] OP_HASH        = 2'b11;

    // FSM states for top-level wrapper
    localparam IDLE     = 3'd0,
               RD_KEY   = 3'd1,
               RD_TEXT  = 3'd2,
               HASH_OP  = 3'd3,
               TX_RES   = 3'd4,
               ACK_HOLD = 3'd5;

    reg [2:0]  cState;       // current FSM state
    reg [4:0]  byte_cnt;     // up to 32 bytes (max 31 → 5 bits)

    localparam [1:0] MEM_ID = 2'b00,
                     AES_ID = 2'b10;

    reg hash_latch; // flag indicates its hash operation to distinguish between acking
    // reg wait_for_wr; // flag indicates its hash result havent get write to the bus
    // ------------------------------------------------------------------------
    // Interface to aes_core_rs
    // ------------------------------------------------------------------------
    // Byte-load handshakes
    reg        core_ld_key_valid;
    reg  [7:0] core_ld_key_byte;
    wire       core_ld_key_ready;

    reg        core_ld_state_valid;
    reg  [7:0] core_ld_state_byte;
    wire       core_ld_state_ready;

    // Start + result
    reg         core_start;
    wire [127:0] core_state_out;
    wire        core_done;
    reg        core_finished;

    // Top-level bookkeeping: “have we loaded a full key/state yet?”
    reg key_loaded;
    reg text_loaded;

    // TX result path
    reg  [7:0] byte_out;
    reg        byte_valid;

    // decode header from first beat only
    reg  [5:0] header_byte; //trim to 6b as we have don't care values
    reg  [2:0] hdr_cnt;       // 0..3: header + 3 addr beats
    wire [1:0] opcode    = header_byte[1:0];
    wire [1:0] source_id = header_byte[3:2];
    wire [1:0] dest_id   = header_byte[5:4];

    // Core instance
    aes_core_rs aes_op (
        .clk            (clk),
        .rst_n          (rst_n),

        .ld_key_valid   (core_ld_key_valid),
        .ld_key_byte    (core_ld_key_byte),
        .ld_key_ready   (core_ld_key_ready),

        .ld_state_valid (core_ld_state_valid),
        .ld_state_byte  (core_ld_state_byte),
        .ld_state_ready (core_ld_state_ready),

        .start          (core_start),
        .state_out      (core_state_out),
        .done           (core_done)
    );

    // ------------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------------
    // We’re "ready" to accept a byte only when:
    //   - we’re in a load state, and
    //   - the core can accept a byte for that path.
    wire ready_payload =
           ((cState == RD_KEY)  && core_ld_key_ready) ||
           ((cState == RD_TEXT) && core_ld_state_ready);

    assign ready_in = (cState == IDLE && hdr_cnt < 3'd4)
                    ? 1'b1
                    : ready_payload;

    assign ack_valid        = (cState == ACK_HOLD);
    assign module_source_id = AES_ID;
    assign data_out         = byte_out;
    assign data_valid       = byte_valid;

    // ------------------------------------------------------------------------
    // Top-level FSM
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cState          <= IDLE;
            byte_cnt        <= 5'd0;
            hdr_cnt         <= 3'd0;
            header_byte     <= 6'd0;

            core_ld_key_valid   <= 1'b0;
            core_ld_key_byte    <= 8'd0;
            core_ld_state_valid <= 1'b0;
            core_ld_state_byte  <= 8'd0;

            core_start      <= 1'b0;

            key_loaded      <= 1'b0;
            text_loaded     <= 1'b0;

            byte_out        <= 8'd0;
            byte_valid      <= 1'b0;
            core_finished   <= 1'b0;

            hash_latch  <= 1'b0;
        end else begin
            // Defaults every cycle
            core_ld_key_valid   <= 1'b0;
            core_ld_state_valid <= 1'b0;
            core_start          <= 1'b0;
            // byte_valid          <= 1'b0;

            case (cState)
                // ----------------------------------------------------------
                // IDLE: accept commands (load key, load text, start, write)
                // ----------------------------------------------------------
                IDLE: begin
                    byte_cnt       <= 5'd0;
                    if (valid_in && (hdr_cnt < 3'd4)) begin
                        if (hdr_cnt == 3'd0) begin
                            // first beat: latch header
                            header_byte <= data_in[5:0];
                        end

                        hdr_cnt <= hdr_cnt + 3'd1;

                        if (hdr_cnt == 3'd3) begin
                            hdr_cnt <= 3'd0;
                            // Start encryption (HASH_OP) — only if both key & text loaded
                            if (dest_id == AES_ID && opcode == OP_HASH) begin
                                if (key_loaded && text_loaded) begin
                                    core_start  <= 1'b1;   // 1-cycle pulse
                                    cState      <= HASH_OP;
                                    text_loaded <= 1'b0;   // consume current plaintext
                                    hash_latch <= 1;
                                end
                            end
                            // Load key
                            else if (source_id == MEM_ID && dest_id == AES_ID &&
                                    opcode == OP_LOAD_KEY && !key_loaded) begin
                                cState    <= RD_KEY;
                                byte_cnt  <= 5'd0;
                            end
                            // Load plaintext
                            else if (source_id == MEM_ID && dest_id == AES_ID &&
                                    opcode == OP_LOAD_TEXT && !text_loaded) begin
                                cState    <= RD_TEXT;
                                byte_cnt  <= 5'd0;
                            end
                            // Write result (only after core_done)
                            else if (opcode  == OP_WRITE_RESULT &&
                                    source_id== AES_ID &&
                                    dest_id  == MEM_ID &&
                                    core_finished) begin
                                cState   <= TX_RES;
                                byte_cnt <= 5'd0;
                            end
                        end
                    end
                end

                // ----------------------------------------------------------
                // RD_KEY: read 32-byte key (MSB-first) and push into core
                // ----------------------------------------------------------
                RD_KEY: begin
                    if (valid_in && ready_in) begin
                        core_ld_key_valid <= 1'b1;
                        core_ld_key_byte  <= data_in;
                        byte_cnt          <= byte_cnt + 1'b1;

                        if (byte_cnt == 5'd31) begin
                            // 32nd byte just accepted
                            key_loaded <= 1'b1;
                            cState     <= IDLE;
                        end
                    end
                end

                // ----------------------------------------------------------
                // RD_TEXT: read 16-byte plaintext (MSB-first) and push into core
                // ----------------------------------------------------------
                RD_TEXT: begin
                    if (valid_in && ready_in) begin
                        core_ld_state_valid <= 1'b1;
                        core_ld_state_byte  <= data_in;
                        byte_cnt            <= byte_cnt + 1'b1;

                        if (byte_cnt == 5'd15) begin
                            // 16th byte just accepted
                            text_loaded <= 1'b1;
                            cState      <= IDLE;
                        end
                    end
                end

                // ----------------------------------------------------------
                // HASH_OP: wait for AES core to finish
                // ----------------------------------------------------------
                HASH_OP: begin
                    if (core_done) begin
                        core_finished <= 1;
                        cState   <= ACK_HOLD;
                        byte_cnt <= 5'd0;
                    end
                end

                // ----------------------------------------------------------
                // TX_RES: stream ciphertext bytes out from core_state_out
                // ----------------------------------------------------------
                TX_RES: begin
                    // If we are not currently holding a valid byte, load one
                    if (!byte_valid && byte_cnt < 5'd16) begin
                        byte_out   <= core_state_out[127 - byte_cnt*8 -: 8];
                        byte_valid <= 1'b1;
                    end

                    // If downstream accepts the current byte
                    if (byte_valid && data_ready) begin
                        byte_valid <= 1'b0;

                        if (byte_cnt == 5'd15) begin
                            cState   <= ACK_HOLD;
                            byte_cnt <= 5'd0;
                        end else begin
                            byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                end

                // ----------------------------------------------------------
                // ACK_HOLD: wait for ack, then return to IDLE
                // ----------------------------------------------------------
                ACK_HOLD: begin
                    if (ack_ready && !hash_latch) begin
                        cState <= IDLE;
                        key_loaded <= 1'b0;   // probably want to preserve key?
                        text_loaded <= 1'b0;
                        hdr_cnt <= 0;
                        byte_cnt <= 0;
                        core_finished <= 1'b0;
                    end else if (ack_ready && hash_latch) begin
                        cState <= IDLE;
                        hdr_cnt <= 0;
                        byte_cnt <= 0;
                    end
                end

                default: cState <= IDLE;
            endcase
        end
    end

endmodule
