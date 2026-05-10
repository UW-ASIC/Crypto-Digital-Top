// Assumes flash is pre-erased and QE bit already set in SR2 (QSPI enabled).
// The startup init sequence has been removed; the FSM enters idle immediately.

`default_nettype none
module mem_txn_fsm(
    input wire clk,
    input wire rst_n,

    // CU
    output wire out_cu_ready,
    input wire in_cu_valid,
    input wire [7:0] in_cu_data,

    input wire in_cu_ready,
    output reg out_cu_valid,
    output reg [7:0] out_cu_data,

    output reg in_fsm_done,

    input wire [23:0] out_address,

    // QSPI
    output reg in_start,
    output reg r_w,
    output reg quad_enable,
    input wire in_spi_done,

    output reg qed,

    output reg out_spi_valid,
    output reg [7:0] out_spi_data,
    input wire in_spi_ready,

    input wire in_spi_valid,
    input wire [7:0] in_spi_data,
    output wire out_spi_ready
);

    //flash opcodes (init opcodes removed)
    localparam [7:0] OPC_WREN   = 8'h06;
    localparam [7:0] FLASH_READ = 8'h6B; // fast read quad output (8 dummy clocks)
    localparam [7:0] FLASH_PP   = 8'h32; // quad input page program
    localparam [7:0] FLASH_RDSR = 8'h05; // read status register 1

    // FSM states (5-bit, 19 states)
    localparam [4:0] idle                   = 5'd0;
    localparam [4:0] dummy                  = 5'd1;
    localparam [4:0] receive_data           = 5'd2;
    localparam [4:0] send_data              = 5'd3;
    localparam [4:0] wait_done              = 5'd4;
    localparam [4:0] send_opcode            = 5'd5;
    localparam [4:0] send_a1                = 5'd6;
    localparam [4:0] send_a2                = 5'd7;
    localparam [4:0] send_a3                = 5'd8;
    localparam [4:0] addr_wait_done         = 5'd9;
    localparam [4:0] gap                    = 5'd10;
    localparam [4:0] spi_wait               = 5'd11;
    localparam [4:0] wren                   = 5'd12;
    localparam [4:0] wip_poll_send          = 5'd13;
    localparam [4:0] wip_poll_rd            = 5'd14;
    localparam [4:0] wip_poll_wait          = 5'd15;
    localparam [4:0] wip_poll_send_wait_done = 5'd16;
    localparam [4:0] wip_poll_rd_wait_done  = 5'd17;
    localparam [4:0] err                    = 5'd18;

    // timing constants — counter shrunk to 16 bits (max: page_program=40000)
    localparam [4:0]  opcode_gap    = 5'd5;
    localparam [15:0] page_program  = 16'd40000;
    localparam [7:0]  pp_max        = 8'd8;

    `ifdef SIMULATION
        localparam [15:0] page_program_sim = 16'd400;
        initial $display("SIMULATION is ON in %m");
    `endif

    // wip poll type (page-program only)
    localparam [1:0] pp   = 2'd1;

    localparam [1:0] aes_id = 2'd2;
    localparam [1:0] RD_KEY = 2'b00, RD_TEXT = 2'b01, WR_RES = 2'b10, INVALID = 2'b11;

    reg [4:0] state, next_state;
    reg [4:0] wren_return_state,  n_wren_return_state;
    reg [4:0] gap_return_state,   n_gap_return_state;
    reg [4:0] wip_return_state,   n_wip_return_state;
    reg [4:0] opaddr_return_state, n_opaddr_return_state;

    // counter shrunk from 27-bit to 16-bit
    reg [15:0] counter, n_counter;
    reg [7:0]  timeout_counts, n_timeout_counts;
    reg [5:0]  total_bytes_left, n_total_bytes_left;

    reg [7:0] opcode_q, n_opcode_q;
    reg [23:0] addr_q,  n_addr_q;
    reg [7:0] n_out_spi_data, n_out_cu_data;
    reg n_out_spi_valid, n_out_cu_valid;
    reg [1:0] wip_poll_type, n_wip_poll_type;
    reg n_qed;

    assign out_cu_ready  = (state == idle) ||
                           (state == send_data && ((!out_spi_valid) || in_spi_ready) && total_bytes_left != 0);
    assign out_spi_ready = (state == wip_poll_rd) || (state == dummy) ||
                           (state == receive_data && (!out_cu_valid || in_cu_ready));

    wire cu_empty_next = !out_cu_valid || (out_cu_valid && in_cu_ready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= idle;
            wren_return_state   <= 5'd0;
            gap_return_state    <= 5'd0;
            wip_return_state    <= 5'd0;
            opaddr_return_state <= 5'd0;
            out_cu_valid        <= 0;
            out_cu_data         <= 0;
            out_spi_valid       <= 0;
            out_spi_data        <= 0;
            counter             <= 0;
            timeout_counts      <= 0;
            total_bytes_left    <= 0;
            opcode_q            <= 0;
            addr_q              <= 0;
            wip_poll_type       <= 0;
            qed                 <= 1; // assume QSPI already enabled in flash SR2
        end else begin
            state               <= next_state;
            wren_return_state   <= n_wren_return_state;
            gap_return_state    <= n_gap_return_state;
            wip_return_state    <= n_wip_return_state;
            opaddr_return_state <= n_opaddr_return_state;
            out_spi_data        <= n_out_spi_data;
            out_spi_valid       <= n_out_spi_valid;
            out_cu_data         <= n_out_cu_data;
            out_cu_valid        <= n_out_cu_valid;
            counter             <= n_counter;
            timeout_counts      <= n_timeout_counts;
            total_bytes_left    <= n_total_bytes_left;
            wip_poll_type       <= n_wip_poll_type;
            addr_q              <= n_addr_q;
            opcode_q            <= n_opcode_q;
            qed                 <= n_qed;
        end
    end

    always @(*) begin
        next_state           = state;
        n_wren_return_state  = wren_return_state;
        n_gap_return_state   = gap_return_state;
        n_wip_return_state   = wip_return_state;
        n_opaddr_return_state = opaddr_return_state;
        n_wip_poll_type      = wip_poll_type;
        n_counter            = counter;
        n_timeout_counts     = timeout_counts;
        n_total_bytes_left   = total_bytes_left;
        n_out_spi_valid      = out_spi_valid;
        n_out_spi_data       = out_spi_data;
        n_out_cu_valid       = out_cu_valid;
        n_out_cu_data        = out_cu_data;
        n_addr_q             = addr_q;
        n_opcode_q           = opcode_q;
        n_qed                = qed;

        in_fsm_done = (state == send_data    && (total_bytes_left == 1 && in_cu_valid && out_cu_ready))
                   || (state == receive_data && (total_bytes_left == 1 && out_spi_ready && in_spi_valid));

        in_start    = 0;
        r_w         = 0;
        quad_enable = 0;

        case (state)

            err: begin
                in_start      = 1'b0;
                r_w           = 1'b0;
                quad_enable   = 1'b0;
                n_out_spi_valid = 1'b0;
                n_out_cu_valid  = 1'b0;
                next_state    = err;
            end

            // ---- shared subroutines ----

            wip_poll_send: begin
                in_start          = 1;
                r_w               = 0;
                quad_enable       = 0;
                next_state        = in_spi_ready ? wip_poll_send_wait_done : wip_poll_send;
                n_out_spi_data    = FLASH_RDSR;
                n_out_spi_valid   = 1;
            end

            wip_poll_send_wait_done: begin
                in_start    = 1;
                r_w         = 0;
                quad_enable = 0;
                next_state  = in_spi_done ? wip_poll_rd_wait_done : wip_poll_send_wait_done;
            end

            wip_poll_rd_wait_done: begin
                in_start        = 1;
                r_w             = 1;
                quad_enable     = 0;
                n_out_spi_valid = 0;
                next_state      = in_spi_done ? wip_poll_rd : wip_poll_rd_wait_done;
            end

            wip_poll_rd: begin
                in_start        = 0;
                r_w             = 1;
                quad_enable     = 0;
                n_out_spi_valid = 0;
                if (in_spi_valid) begin
                    if (in_spi_data[0]) begin
                        // WIP still set — back off and retry
                        `ifdef SIMULATION
                            n_counter = page_program_sim;
                        `else
                            n_counter = page_program;
                        `endif
                        next_state        = (timeout_counts >= pp_max) ? err : wip_poll_wait;
                        n_timeout_counts  = timeout_counts + 1;
                    end else begin
                        next_state        = gap;
                        n_gap_return_state = wip_return_state;
                        n_counter         = {11'b0, opcode_gap};
                        n_timeout_counts  = 0;
                    end
                end
            end

            wip_poll_wait: begin
                in_start   = 0;
                r_w        = 0;
                if (counter == 0)
                    next_state = wip_poll_send;
                else begin
                    n_counter  = counter - 1;
                    next_state = wip_poll_wait;
                end
            end

            spi_wait: begin
                in_start        = 1;
                n_out_spi_valid = 0;
                if (in_spi_done) begin
                    next_state         = gap;
                    n_counter          = {11'b0, opcode_gap};
                end
            end

            gap: begin
                in_start   = 0;
                n_counter  = (counter == 0) ? 0 : counter - 1;
                next_state = (counter == 0 && cu_empty_next) ? gap_return_state : gap;
                if (out_cu_valid && in_cu_ready)
                    n_out_cu_valid = 1'b0;
            end

            wren: begin
                in_start        = 1;
                r_w             = 0;
                quad_enable     = 0;
                n_out_spi_data  = OPC_WREN;
                n_out_spi_valid = 1;
                next_state      = in_spi_ready ? spi_wait : wren;
                n_gap_return_state = wren_return_state;
            end

            send_opcode: begin
                in_start    = 1'b1;
                r_w         = 1'b0;
                quad_enable = 1'b0;
                if (!out_spi_valid) begin
                    n_out_spi_data  = opcode_q;
                    n_out_spi_valid = 1'b1;
                end
                if (out_spi_valid && in_spi_ready) begin
                    n_out_spi_valid = 1'b0;
                    next_state      = send_a1;
                end
            end

            send_a1: begin
                in_start    = 1'b1;
                r_w         = 1'b0;
                quad_enable = 1'b0;
                if (!out_spi_valid) begin
                    n_out_spi_data  = addr_q[23:16];
                    n_out_spi_valid = 1'b1;
                end
                if (out_spi_valid && in_spi_ready) begin
                    n_out_spi_valid = 1'b0;
                    next_state      = send_a2;
                end
            end

            send_a2: begin
                in_start    = 1'b1;
                r_w         = 1'b0;
                quad_enable = 1'b0;
                if (!out_spi_valid) begin
                    n_out_spi_data  = addr_q[15:8];
                    n_out_spi_valid = 1'b1;
                end
                if (out_spi_valid && in_spi_ready) begin
                    n_out_spi_valid = 1'b0;
                    next_state      = send_a3;
                end
            end

            send_a3: begin
                in_start    = 1'b1;
                r_w         = 1'b0;
                quad_enable = 1'b0;
                if (!out_spi_valid) begin
                    n_out_spi_data  = addr_q[7:0];
                    n_out_spi_valid = 1'b1;
                end
                if (out_spi_valid && in_spi_ready) begin
                    n_out_spi_valid = 1'b0;
                    next_state      = addr_wait_done;
                end
            end

            addr_wait_done: begin
                in_start        = 1'b1;
                r_w             = 1'b0;
                quad_enable     = 1'b0;
                n_out_spi_valid = 1'b0;
                next_state      = in_spi_done ? opaddr_return_state : addr_wait_done;
            end

            // ---- normal flow ----

            idle: begin
                n_out_cu_data   = 0;
                n_out_cu_valid  = 0;
                n_out_spi_data  = 0;
                n_out_spi_valid = 0;
                if (in_cu_valid && out_cu_ready) begin
                    case (in_cu_data[1:0])
                        RD_KEY: begin
                            n_total_bytes_left  = 32;
                            n_opcode_q          = FLASH_READ;
                            n_addr_q            = out_address;
                            next_state          = wip_poll_send;
                            n_wip_poll_type     = pp;
                            n_wip_return_state  = send_opcode;
                            n_opaddr_return_state = dummy;
                        end
                        RD_TEXT: begin
                            n_total_bytes_left  = (in_cu_data[5:4] == aes_id) ? 16 : 32;
                            n_opcode_q          = FLASH_READ;
                            n_addr_q            = out_address;
                            next_state          = wip_poll_send;
                            n_wip_poll_type     = pp;
                            n_wip_return_state  = send_opcode;
                            n_opaddr_return_state = dummy;
                        end
                        WR_RES: begin
                            n_total_bytes_left  = (in_cu_data[3:2] == aes_id) ? 16 : 32;
                            n_opcode_q          = FLASH_PP;
                            n_addr_q            = out_address;
                            next_state          = wip_poll_send;
                            n_wip_poll_type     = pp;
                            n_wip_return_state  = wren;
                            n_wren_return_state = send_opcode;
                            n_opaddr_return_state = send_data;
                        end
                        INVALID: next_state = idle;
                        default:;
                    endcase
                end
            end

            dummy: begin
                in_start    = 1'b1;
                r_w         = 1'b1;
                quad_enable = 1'b0;
                next_state  = (in_spi_valid && out_spi_ready) ? receive_data : dummy;
            end

            receive_data: begin
                in_start    = 1'b1;
                r_w         = 1'b1;
                quad_enable = 1'b1;
                if (out_cu_valid && in_cu_ready)
                    n_out_cu_valid = 1'b0;
                if (out_spi_ready && in_spi_valid) begin
                    n_out_cu_data  = in_spi_data;
                    n_out_cu_valid = 1;
                    if (total_bytes_left == 1) begin
                        n_total_bytes_left = 0;
                        next_state         = gap;
                        n_counter          = {11'b0, opcode_gap};
                        n_gap_return_state = idle;
                    end else begin
                        n_total_bytes_left = total_bytes_left - 1;
                    end
                end
            end

            send_data: begin
                in_start    = 1'b1;
                r_w         = 1'b0;
                quad_enable = 1'b1;
                if (out_spi_valid && in_spi_ready) begin
                    n_out_spi_valid = 0;
                    if (total_bytes_left == 0)
                        next_state = wait_done;
                end
                if (in_cu_valid && out_cu_ready) begin
                    n_out_spi_data     = in_cu_data;
                    n_out_spi_valid    = 1'b1;
                    n_total_bytes_left = total_bytes_left - 1;
                end
            end

            wait_done: begin
                in_start    = 1'b1;
                r_w         = 1'b0;
                quad_enable = 1'b1;
                next_state  = in_spi_done ? gap : wait_done;
                n_counter   = in_spi_done ? {11'b0, opcode_gap} : counter;
                n_gap_return_state = idle;
            end

            default: ;
        endcase
    end

    wire _unused = &{1'b0, wip_poll_type};
endmodule

`default_nettype wire
