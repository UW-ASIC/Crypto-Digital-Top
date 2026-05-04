`default_nettype none

module data_bus_ctrl (
    input wire clk,
    input wire rst_n,
    // data bus handshake
    input wire [7:0] data_on_bus,
    input wire valid_on_bus,

    // ready signal from module
    input wire rdy_mem,
    input wire rdy_aes,
    input wire rdy_sha,

    // ack bus handshake
    input wire[1:0] id_on_ack,
    input wire ready_on_ack,
    input wire valid_on_ack,
    
    // 1bit per signal
    output reg [3:0] rdy_rd_grant, // ready read grant
    output reg [3:0] dv_rd_grant,  // data/valid read grant
    // encoded
    output reg [1:0] data_sel,

    // ready output
    output reg rdy_to_owner
    // output reg [1:0] rdy_sel
);
    //src/dest ids
    localparam [1:0] ctrl_id = 2'b11, mem_id = 2'b00, aes_id = 2'b10, sha_id = 2'b01;
    // ? tbd 
    localparam [3:0] mem_1b  = (4'b0001 << mem_id);
    localparam [3:0] sha_1b  = (4'b0001 << sha_id);
    localparam [3:0] aes_1b  = (4'b0001 << aes_id);
    localparam [3:0] ctrl_1b = (4'b0001 << ctrl_id);
    // default control ? after opcode byte handshaked goes to tansmission, back when ack bus handshake
    localparam [1:0] idle = 2'd0, op_wait_ready = 2'd1, addr = 2'd2, module_transmission = 2'd3;

    // mux sel
    reg [1:0] n_data_sel;
    // rd grant
    reg [3:0] n_rdy_rd_grant, n_dv_rd_grant;
    // state of the bus
    reg [1:0] state, n_state;
    // counter if mem include
    reg [1:0] counter, n_counter;
    
    // slice opcode
    wire [1:0] dest, src, opcode;
    // latch src and dest
    reg[1:0] dest_latch, src_latch, n_dest_latch, n_src_latch;
    assign dest = data_on_bus[5:4], src = data_on_bus[3:2], opcode = data_on_bus[1:0];

    // handshakes on data/ack bus
    wire ack_bus_fire;
    assign ack_bus_fire = valid_on_ack && ready_on_ack && (id_on_ack == src_latch);

    // opcode format matching
    wire rd_key_fire, rd_txt_fire, wr_txt_fire, hash_fire; 
    assign rd_key_fire = (opcode == 2'b00) && (dest == aes_id) && (src == mem_id);
    assign rd_txt_fire = (opcode == 2'b01) && ((dest == aes_id) || (dest == sha_id)) && (src == mem_id);
    assign wr_txt_fire = (opcode == 2'b10) && (dest == mem_id) && ((src == aes_id) || (src == sha_id));
    assign hash_fire = (opcode == 2'b11) && ((dest == aes_id) || (dest == sha_id));

    // src ready and dest ready only for opcode
    reg src_rdy, dest_rdy;
    

    always @(*) begin
        if (state == idle) begin
            src_rdy = (src == mem_id) ? rdy_mem : (src == aes_id) ? rdy_aes : (src == sha_id) ? rdy_sha : 0;
            dest_rdy = (dest == mem_id) ? rdy_mem : (dest == aes_id) ? rdy_aes : (dest == sha_id) ? rdy_sha : 0;            
        end else begin
            src_rdy = (src_latch == mem_id) ? rdy_mem : (src_latch == aes_id) ? rdy_aes : (src_latch == sha_id) ? rdy_sha : 0;
            dest_rdy = (dest_latch == mem_id) ? rdy_mem : (dest_latch == aes_id) ? rdy_aes : (dest_latch == sha_id) ? rdy_sha : 0;                  
        end
    end

    // sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            counter <= 0;

            data_sel <= ctrl_id;
            rdy_rd_grant <= ctrl_1b;
            dv_rd_grant <= ctrl_1b;

            dest_latch <= 0;
            src_latch <= 0;

            // rdy_to_owner <= 0;
        end else begin
            state <= n_state;
            counter <= n_counter;

            data_sel <= n_data_sel;
            rdy_rd_grant <= n_rdy_rd_grant;
            dv_rd_grant <= n_dv_rd_grant;

            dest_latch <= n_dest_latch;
            src_latch <= n_src_latch;

            // rdy_to_owner <= n_rdy_to_owner;
        end
    end 
    
    // next state/sel computing
    always @(*) begin
        // comb default
        n_state = state;
        n_counter = counter;

        n_data_sel = data_sel;
        n_rdy_rd_grant = rdy_rd_grant;
        n_dv_rd_grant = dv_rd_grant;

        n_dest_latch = dest_latch;
        n_src_latch = src_latch;

        rdy_to_owner = 0;
        // n_rdy_to_owner = rdy_to_owner;

        case (state)
            // when ctrl owns the bus by default
            idle: begin
                n_counter = 0;
                n_dest_latch = 0;
                n_src_latch = 0;
                // control owns the bus by default
                n_data_sel = ctrl_id;
                // default
                rdy_to_owner = 1;
                // CTRL RD
                n_rdy_rd_grant = ctrl_1b;
                n_dv_rd_grant = ctrl_1b;

                if(valid_on_bus) begin
                    // keep same
                    if (hash_fire) begin
                        // id to 1hot decode
                        n_dv_rd_grant = (dest == aes_id) ? aes_1b : (dest == sha_id) ? sha_1b : ctrl_1b;

                        n_dest_latch = dest;  // remember AES or SHA
                        rdy_to_owner = 0; //stall for 1 cycle 
                        n_state = op_wait_ready;
                    end else if(rd_key_fire || rd_txt_fire || wr_txt_fire) begin
                        // handshake
                        rdy_to_owner = 0;
                        n_state = op_wait_ready;
                        // let source module see opcode, if not mem only 1byte for handshake
                        n_src_latch = src;
                        n_dest_latch = dest;
                        // set src
                        n_dv_rd_grant = set(n_dv_rd_grant, src);
                        n_dv_rd_grant = set(n_dv_rd_grant, dest);
                        
                    end else begin
                        // ggs
                    end
                end                
            end 
            // when the opcode is xx xx xx 11 hashing operation, wait for fire (ideally 1 cycle but could more than that if sha/aes is not ready)
            op_wait_ready: begin
                n_data_sel = ctrl_id;
                n_rdy_rd_grant = ctrl_1b;

                if (opcode == 2'b11) begin
                    // hash case: only dest needs to see opcode
                    rdy_to_owner = dest_rdy;

                    if (valid_on_bus && dest_rdy) begin
                        n_state = idle;
                        n_dv_rd_grant = ctrl_1b;
                        n_rdy_rd_grant = ctrl_1b;
                        n_dest_latch = 0;
                        n_src_latch = 0;
                    end
                end else begin
                    // normal rd/wr case: src and dest both need to see opcode
                    rdy_to_owner = src_rdy & dest_rdy;

                    if (valid_on_bus && src_rdy && dest_rdy) begin
                        // opcode was accepted safely
                        n_state = addr;
                    end
                end
            end
            // when src/dest contains mem, count 3 handshake update ownership
            addr: begin
                // only mem needs handshake
                rdy_to_owner = rdy_mem;

                // count the handshake
                n_counter = (valid_on_bus && rdy_mem) ? counter + 1: counter;
                // when 2 beat handshaked and the third handshake 
                if (counter == 2 && valid_on_bus && rdy_mem) begin
                    n_state = module_transmission;
                    n_data_sel = src_latch;
                    // set ready read grant to src module
                    n_rdy_rd_grant = set(4'b0000, src_latch);
                    // reset counter
                    n_counter = 0;
                    // rd grant reset
                    n_dv_rd_grant = clr(n_dv_rd_grant, src_latch);
                end
            end
            // src module now owns the bus and ownership will be return upon ack handshake on ack bus
            module_transmission: begin
                n_counter = 0;
                n_data_sel = src_latch;
                rdy_to_owner = dest_rdy;

                if (ack_bus_fire) begin
                    n_data_sel = ctrl_id;
                    rdy_to_owner = 0;
                    n_dv_rd_grant = clr(n_dv_rd_grant, dest_latch);
                    n_state = idle;
                    n_src_latch = 0;
                    n_dest_latch = 0;
                end
            end

            default:; 
        endcase

    end
    // set decode based on id
    function [3:0] set;
        input [3:0] grant;
        input [1:0] id;
        begin
            set = grant;
            case (id)
                mem_id:  set = set | mem_1b;
                ctrl_id: set = set | ctrl_1b;
                aes_id:  set = set | aes_1b;
                sha_id:  set = set | sha_1b;
                default: ;
            endcase
        end
    endfunction
    //clr decode based on id
    function [3:0] clr;
        input [3:0] grant;
        input [1:0] id;
        begin
            clr = grant;
            case (id)
                mem_id:  clr = clr & (~mem_1b);
                ctrl_id: clr = clr & (~ctrl_1b);
                aes_id:  clr = clr & (~aes_1b);
                sha_id:  clr = clr & (~sha_1b);
                default: ;
            endcase
        end
    endfunction
endmodule