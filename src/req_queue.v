module req_queue #(
    parameter ADDRW = 24,
    parameter OPCODEW = 2,
    parameter QDEPTH = 2
) (
    input wire clk,
    input wire rst_n,
    input wire valid_in,
    input wire ready_in_aes,

    input wire [OPCODEW - 1:0] opcode,
    input wire [ADDRW - 1:0] key_addr,
    input wire [ADDRW - 1:0] text_addr,
    input wire [ADDRW - 1:0] dest_addr,

    output wire [3 * ADDRW + OPCODEW - 1:0] instr_aes,
    output wire valid_out_aes,
    output wire ready_out_aes
);

    integer j;

    localparam integer AES_INSTRW = 3 * ADDRW + OPCODEW;
    localparam integer IDXW = (QDEPTH <= 1) ? 1 : $clog2(QDEPTH);
    localparam [IDXW - 1:0] LAST_IDX = IDXW'(QDEPTH - 1);

    reg [AES_INSTRW - 1:0] aesQueue [QDEPTH - 1:0];
    reg [IDXW - 1:0] aesReadIdx;
    reg [IDXW - 1:0] aesWriteIdx;
    reg aesFull;

    wire aes_empty = aesReadIdx == aesWriteIdx;

    assign ready_out_aes = (aesReadIdx != aesWriteIdx || !aesFull) && rst_n;
    assign valid_out_aes = (aesReadIdx != aesWriteIdx || aesFull) && rst_n;
    assign instr_aes = aesQueue[aesReadIdx];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < QDEPTH; j = j + 1) aesQueue[j] <= {AES_INSTRW{1'b0}};
            aesReadIdx  <= {IDXW{1'b0}};
            aesWriteIdx <= {IDXW{1'b0}};
            aesFull     <= 0;
        end else begin
            if (valid_in && ready_out_aes) begin
                aesQueue[aesWriteIdx] <= {opcode, key_addr, text_addr, dest_addr};
                if (aesWriteIdx == LAST_IDX) begin
                    if (aesReadIdx == {IDXW{1'b0}}) aesFull <= 1;
                    aesWriteIdx <= {IDXW{1'b0}};
                end else begin
                    if (aesReadIdx == aesWriteIdx + 1) aesFull <= 1;
                    aesWriteIdx <= aesWriteIdx + 1;
                end
            end

            if (ready_in_aes && !aes_empty) begin
                if (aesReadIdx == LAST_IDX)
                    aesReadIdx <= {IDXW{1'b0}};
                else
                    aesReadIdx <= aesReadIdx + 1;
                aesFull <= 0;
            end
        end
    end

endmodule
