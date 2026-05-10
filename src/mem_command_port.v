/* 
1.     output reg [2:0] fsm_opcode to output reg [1:0] fsm_opcode,
2.     ready: combinational driven by next chain ready
3.     wire [2:0] dest_id = in_bus_data[5:4]; to wire [1:0] dest_id = in_bus_data[5:4];
4.     update forwarding logic: only forward when output valid is low(empty)/downstream ready is high
5.     opcode condition

*/
`default_nettype none
module mem_command_port(
    input wire clk,
    input wire rst_n,

    // --- Bus ---
    input wire in_bus_valid,
    input wire in_bus_ready,
    input wire [7:0] in_bus_data,

    output reg [7:0] out_bus_data,
    output wire out_bus_ready,
    output reg out_bus_valid,
    
    // --- Ack Bus ---
    input wire in_ack_bus_owned,
    output reg out_ack_bus_request,
    output reg [1:0] out_ack_bus_id,

    // --- Transaction FSM ---
    output reg out_fsm_valid,
    output wire out_fsm_ready,
    output reg [7:0] out_fsm_data,

    input wire in_fsm_ready,
    input wire in_fsm_valid,
    input wire [7:0] in_fsm_data,
    input wire in_fsm_done,
    
    // output reg out_fsm_enc_type,
    // output reg [1:0] fsm_opcode,
    output reg [23:0] out_address
);

    localparam MEM_ID = 2'b00;

    localparam RD_KEY = 2'b00;
    localparam RD_TEXT = 2'b01;
    localparam WR_RES = 2'b10;
    localparam OTHER = 2'b11;

    localparam [2:0] IDLE               = 3'd0;
    localparam [2:0] PASS_CMD           = 3'd1;
    localparam [2:0] PASS_CMD_WAIT_READY = 3'd2;
    localparam [2:0] PERFORM_TRANSFER   = 3'd3;
    localparam [2:0] TRY_ACK            = 3'd4;
    localparam [2:0] ACK_RECEIVED       = 3'd5;

    reg [1:0] fsm_opcode;

    reg [2:0] state;
    reg [4:0] counter; // counts 0,8,16,24 — 5 bits sufficient

    reg fsm_done_latch;
    reg [5:0] internal_opcode; // only bits [5:0] used by FSM (dest/src/opcode)
    // wire enc_dec = in_bus_data[7];
    // wire [1:0] dest_id = in_bus_data[5:4];
    // wire [1:0] src_id = in_bus_data[3:2];
    // wire [1:0] opcode = in_bus_data[1:0];
    wire [1:0] dest_id = in_bus_data[5:4];
    wire [1:0] src_id = in_bus_data[3:2];
    wire [1:0] opcode;
    // mode
    wire wr = (state == PERFORM_TRANSFER) && (fsm_opcode[1]);
    wire rd = (state == PERFORM_TRANSFER) && ((!fsm_opcode[1]));
    assign opcode  = (state == IDLE && in_bus_valid) ? in_bus_data[1:0] : 2'b00 ;
    // combinational drive ready
    assign out_bus_ready = (state == IDLE) || (state == PASS_CMD && counter < 23) || 
    (wr && (!out_fsm_valid || in_fsm_ready) && ( !fsm_done_latch ) );

    assign out_fsm_ready = rd && (!out_bus_valid || in_bus_ready);
    
    // wire out_fsm_empty_next = !out_fsm_valid || in_fsm_ready;
    wire out_bus_empty_next = !out_bus_valid || in_bus_ready;

    wire bus_fr_wr = wr && in_bus_valid && out_bus_ready;
    wire fsm_fr_wr = wr && out_fsm_valid && in_fsm_ready;

    wire fsm_fr_rd = rd && in_fsm_valid && out_fsm_ready;
    wire bus_fr_rd = rd && out_bus_valid && in_bus_ready;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            out_bus_data <= 0;
            out_bus_valid <= 0;
            out_ack_bus_id <= 0;
            out_ack_bus_request <= 0;
            out_fsm_valid <= 0;
            out_fsm_data <= 0;
            counter <= 0;
            state <= IDLE;
            out_address <= 0;
            fsm_opcode<=0;
            // out_fsm_enc_type <= 0;
            internal_opcode <= 0;
        end else begin
            case(state)
                IDLE: begin
                    counter <= 0;
                    out_bus_valid <= 0;
                    out_fsm_valid <= 0;
                    out_ack_bus_request <= 0;
                    internal_opcode <= 0;
                    if(out_bus_ready &&  in_bus_valid && (opcode != OTHER)) begin
                        case(opcode)
                            RD_KEY, RD_TEXT: begin
                                if(src_id == MEM_ID) state <= PASS_CMD;
                            end
                            WR_RES: begin
                                if(dest_id == MEM_ID) state <= PASS_CMD;
                            end
                        default: state <= IDLE;
                        endcase
                        fsm_opcode <= opcode;
                        // out_fsm_enc_type <= enc_dec;
                        internal_opcode <= in_bus_data[5:0];
                    end
                end

                PASS_CMD: begin
                    if(in_bus_valid && out_bus_ready) begin
                        out_address[counter + 7 -: 8] <= in_bus_data;
                        counter <= counter + 8;
                        out_fsm_data <= {2'b0, internal_opcode};
                    end
                    if(counter >= 23) begin
                        out_fsm_valid <= 1;
                        state <= PASS_CMD_WAIT_READY;
                    end
                end
                PASS_CMD_WAIT_READY: begin
                    out_fsm_valid <= 1'b1;
                    out_fsm_data  <= internal_opcode;
                    if (out_fsm_valid && in_fsm_ready) begin
                        // command accepted by FSM
                        out_fsm_valid <= 0;
                        state <= PERFORM_TRANSFER;
                    end
                end
                PERFORM_TRANSFER: begin
                    // bus - cu - fsm
                    if (fsm_opcode == WR_RES) begin
                        // only accept if output to fsm is empty or fsm ready
                        if (fsm_fr_wr && !bus_fr_wr) begin
                            out_fsm_valid <= 0;
                        end
                        
                        if (bus_fr_wr) begin
                            out_fsm_valid <= 1;
                            out_fsm_data  <= in_bus_data;
                        end
                        if (fsm_done_latch || in_fsm_done) begin
                            state <= IDLE;
                        end
                    end
                    // fsm - cu - bus   
                    else if (!fsm_opcode[1])begin
                        // only accept if output to bus is empty or bus ready
                        if (bus_fr_rd && !fsm_fr_rd) begin
                            out_bus_valid <= 0;
                        end

                        if (fsm_fr_rd) begin
                            out_bus_valid <= 1;
                            out_bus_data <= in_fsm_data;
                        end
                        // proceed when there is no byte waiting on databus and no byte pending transfer from fsm
                        if (fsm_done_latch && out_bus_empty_next && !in_fsm_valid) begin
                            state <= TRY_ACK;
                        end
                    end
                end
                        
                TRY_ACK: begin
                    out_ack_bus_request <= 1;
                    out_ack_bus_id <= MEM_ID;
                    if(in_ack_bus_owned) state <= ACK_RECEIVED;
                end

                ACK_RECEIVED: begin
                    out_ack_bus_request <= 0;
                    out_ack_bus_id <= MEM_ID;   
                     state <= IDLE;                   
                end

                default:;
            endcase
        end
    end
    // in fsm done latch
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) fsm_done_latch <= 1'b0;
        else if (state == IDLE) fsm_done_latch <= 1'b0;
        else if (in_fsm_done) fsm_done_latch <= 1'b1;
    end
endmodule
