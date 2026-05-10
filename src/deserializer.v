`default_nettype none

module deserializer #(
    parameter ADDRW   = 24,
    parameter OPCODEW = 2
) (
    // INPUTS: clk, rst_n, spi_clk, mosi, cs_n, aes_ready_in
    input  wire               clk,
    input  wire               rst_n,
    input  wire               spi_clk,
    input  wire               mosi,
    input  wire               cs_n,
    input  wire               aes_ready_in,
    // OUTPUTS: opcode[1:0], key_addr[ADDRW-1:0], text_addr[ADDRW-1:0], dest_addr, valid_out
    output reg  [OPCODEW-1:0] opcode,
    output reg  [ADDRW-1:0]   key_addr,
    output reg  [ADDRW-1:0]   text_addr,
    output reg  [ADDRW-1:0]   dest_addr,
    output reg                valid_out
);

    // Total instruction width: [valid(1b), opcode(OPCODEW), key_addr, text_addr, dest_addr]
    localparam integer SHIFT_W = 1 + OPCODEW + (3 * ADDRW);
    localparam integer CW = $clog2(SHIFT_W + 1);
    localparam [CW-1:0] CNT_FULL = CW'(SHIFT_W) - 1;

    // synchronize
    reg [1:0] r_clk;
    reg [1:0] r_cs_n;
    reg [1:0] r_mosi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_clk  <= 2'b00;
            r_cs_n <= 2'b11;
            r_mosi <= 2'b00;
        end else begin
            r_clk  <= {r_clk[0],  spi_clk};
            r_cs_n <= {r_cs_n[0], cs_n};
            r_mosi <= {r_mosi[0], mosi};
        end
    end

    wire clk_posedge = (r_clk == 2'b01);

    reg [CW-1:0]      cnt;
    reg [SHIFT_W-1:0] shift_reg;
    reg               busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= {CW{1'b0}};
            shift_reg <= {SHIFT_W{1'b0}};
            busy      <= 1'b0;
            opcode    <= {OPCODEW{1'b0}};
            key_addr  <= {ADDRW{1'b0}};
            text_addr <= {ADDRW{1'b0}};
            dest_addr <= {ADDRW{1'b0}};
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b0;

            if (~r_cs_n[1]) begin
                if (clk_posedge && !busy) begin
                    shift_reg <= {shift_reg[SHIFT_W-2:0], r_mosi[1]};
                    if (cnt == CNT_FULL) begin
                        busy <= 1'b1;
                        cnt  <= {CW{1'b0}};
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
            end else begin
                if (!busy) begin
                    cnt       <= {CW{1'b0}};
                    shift_reg <= {SHIFT_W{1'b0}};
                end
            end

            // Dispatch when full word captured and AES queue is ready
            if (busy && aes_ready_in) begin
                opcode    <= shift_reg[SHIFT_W-2 : 3*ADDRW];
                key_addr  <= shift_reg[3*ADDRW-1 : 2*ADDRW];
                text_addr <= shift_reg[2*ADDRW-1 : ADDRW];
                dest_addr <= shift_reg[ADDRW-1   : 0];
                valid_out <= shift_reg[SHIFT_W-1];
                busy      <= 1'b0;
            end
        end
    end
endmodule
