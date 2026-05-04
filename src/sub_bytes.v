// ============================================================================
// SubBytes + ShiftRows, 1-byte-per-2-cycles using shared S-box
// - Reads from a 128-bit snapshot state_in (pre-round state)
// - For each input byte index j_in (0..15), computes:
//     j_out = ShiftRows(j_in) in column-major AES layout
// - Emits:
//     we       : 1 when byte_out/byte_idx are valid
//     byte_idx : destination index in state_reg (0..15)
//     byte_out : S-box(SubBytes) value for that location
// ============================================================================
module subbytes (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,        // pulse for 1 cycle when state_in is valid
    input  wire [127:0] state_in,    // snapshot of state at start of round

    output reg         done,         // 1-cycle pulse when last byte written
    output reg         we,           // write-enable for byte_out/byte_idx
    output reg  [3:0]  byte_idx,     // destination byte index (0..15)
    output reg  [7:0]  byte_out,     // S-box( state_in[...] ) after ShiftRows

    // external S-box (shared with key schedule)
    output reg  [7:0]  sbox_in,
    input  wire [7:0]  sbox_out
);

    // FSM for streaming bytes
    reg        active;               // 1 while processing all 16 bytes
    reg        phase;                // 0 = ISSUE (drive sbox_in), 1 = CAPTURE
    reg [3:0]  idx_in;               // input byte index j_in = 0..15

    // Helper: MSB-aligned byte access: j -> [127-8*j -: 8]
    function automatic [7:0] get_byte(input [127:0] v, input [3:0] j);
        get_byte = v[127 - 8*j -: 8];
    endfunction

    // Helper: ShiftRows index mapping in column-major layout
    // j = 4*c + r, where r = row (0..3), c = col (0..3)
    // ShiftRows: row r is rotated left by r bytes => c_out = (c_in - r) mod 4
    function automatic [3:0] sr_index(input [3:0] j_in);
        reg [1:0] r;
        reg [1:0] c_in;
        reg [1:0] c_out;
        begin
            r    = j_in[1:0];      // low bits = row
            c_in = j_in[3:2];      // high bits = column
            c_out = c_in - r;      // 2-bit subtract wraps mod 4
            sr_index = {c_out, r}; // j_out = 4*c_out + r
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active   <= 1'b0;
            phase    <= 1'b0;
            idx_in   <= 4'd0;
            done     <= 1'b0;
            we       <= 1'b0;
            byte_idx <= 4'd0;
            byte_out <= 8'h00;
            sbox_in  <= 8'h00;
        end else begin
            // defaults each cycle
            done <= 1'b0;
            we   <= 1'b0;   // only true in CAPTURE on valid byte

            if (start && !active) begin
                // Start new SubBytes+ShiftRows pass
                active   <= 1'b1;
                phase    <= 1'b0;   // ISSUE first
                idx_in   <= 4'd0;
            end else if (active) begin
                if (!phase) begin
                    // ISSUE phase: drive S-box input for current byte index
                    sbox_in <= get_byte(state_in, idx_in);
                    phase   <= 1'b1;
                end else begin
                    // CAPTURE phase: S-box result corresponds to previous sbox_in
                    byte_out <= sbox_out;
                    byte_idx <= sr_index(idx_in);
                    we       <= 1'b1;
                    phase    <= 1'b0;

                    if (idx_in == 4'd15) begin
                        // last byte completed
                        active <= 1'b0;
                        done   <= 1'b1;
                    end else begin
                        idx_in <= idx_in + 4'd1;
                    end
                end
            end
        end
    end

endmodule
