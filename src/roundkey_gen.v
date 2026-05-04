module roundkeygen_1lane (
    input  wire        clk,
    input  wire        rst_n,

    // Sliding window {w0..w7} from core
    input  wire [31:0] w0, w1, w2, w3,
    input  wire [31:0] w4, w5, w6, w7,
    input  wire [2:0]  rcon_idx_in,
    input  wire        use_rcon_in,   // AES-256: 1 for i%8==0, 0 for i%8==4

    input  wire        start,         // pulse: compute next quartet
    output reg  [31:0] w8, w9, w10, w11,
    output reg  [2:0]  rcon_idx_out,
    output reg         use_rcon_out,
    output reg         done,

    // shared S-box
    output reg  [7:0]  sbox_in,
    input  wire [7:0]  sbox_out
);
    // Rcon table
    // wire [31:0] rcon [0:7];
    // assign rcon[0] = 32'h01_00_00_00;
    // assign rcon[1] = 32'h02_00_00_00;
    // assign rcon[2] = 32'h04_00_00_00;
    // assign rcon[3] = 32'h08_00_00_00;
    // assign rcon[4] = 32'h10_00_00_00;
    // assign rcon[5] = 32'h20_00_00_00;
    // assign rcon[6] = 32'h40_00_00_00;
    // assign rcon[7] = 32'h80_00_00_00;
    wire [7:0] rcon_hi;

    function automatic [31:0] rotword (input [31:0] w);
        rotword = {w[23:0], w[31:24]};
    endfunction

    reg        active;
    reg        phase;        // 0 = ISSUE, 1 = CAPTURE
    reg [1:0]  byte_cnt;     // 0..3 instead of 0..3 in idx

    reg [31:0] src_word;
    reg [23:0] sub_word;

    reg [2:0]  rcon_idx;
    reg        use_rcon;

    // new SubWord after capturing this S-box output
    wire [31:0] subword_new = {sub_word[23:0], sbox_out};

    // t = SubWord (optionally XOR Rcon)
    assign rcon_hi = 8'h01 << rcon_idx;
    wire [31:0] t_word = {subword_new[31:24] ^ (use_rcon ? rcon_hi : 8'h00), subword_new[23:0]};

    // next quartet values
    wire [31:0] w8_next  = w0 ^ t_word;
    wire [31:0] w9_next  = w1 ^ w0 ^ t_word;
    wire [31:0] w10_next = w2 ^ w1 ^ w0 ^ t_word;
    wire [31:0] w11_next = w3 ^ w2 ^ w1 ^ w0 ^ t_word;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active        <= 1'b0;
            phase         <= 1'b0;
            byte_cnt      <= 2'd0;
            src_word      <= 32'd0;
            sub_word      <= 24'd0;
            rcon_idx      <= 3'd0;
            use_rcon      <= 1'b1;

            w8            <= 32'd0;
            w9            <= 32'd0;
            w10           <= 32'd0;
            w11           <= 32'd0;
            rcon_idx_out  <= 3'd0;
            use_rcon_out  <= 1'b1;
            done          <= 1'b0;
            sbox_in       <= 8'h00;

        end else begin
            done <= 1'b0;

            if (start && !active) begin
                // Start new quartet
                active   <= 1'b1;
                phase    <= 1'b0;        // ISSUE first
                byte_cnt <= 2'd0;
                sub_word <= 24'd0;

                rcon_idx <= rcon_idx_in;
                use_rcon <= use_rcon_in;

                // choose source word, apply RotWord if needed
                src_word <= use_rcon_in ? rotword(w7) : w7;

            end else if (active) begin
                if (!phase) begin
                    // ISSUE: present next byte to S-box and shift src_word
                    sbox_in <= src_word[31:24];
                    src_word <= {src_word[23:0], 8'h00};
                    phase    <= 1'b1;

                end else begin
                    // CAPTURE: shift sub_word and append S-box output
                    sub_word <= subword_new[23:0];

                    if (byte_cnt == 2'd3) begin
                        // full SubWord now in subword_new / sub_word_next

                        w8  <= w8_next;
                        w9  <= w9_next;
                        w10 <= w10_next;
                        w11 <= w11_next;

                        rcon_idx_out <= use_rcon ? (rcon_idx + 3'd1) : rcon_idx;
                        use_rcon_out <= ~use_rcon;

                        active   <= 1'b0;
                        phase    <= 1'b0;
                        byte_cnt <= 2'd0;
                        done     <= 1'b1;

                    end else begin
                        // continue with next byte
                        byte_cnt <= byte_cnt + 2'd1;
                        phase    <= 1'b0;
                    end
                end
            end
        end
    end
    /* verilator lint_on BLKSEQ */
    wire _unused = &{w4, w5, w6};

endmodule
