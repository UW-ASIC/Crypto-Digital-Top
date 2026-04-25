`default_nettype none

module global_arbiter (
    input wire clk,
    input wire rst_n,

    // data local interfaces -> global arbiter
    // packed format:
    //   [9]   ready
    //   [8]   valid
    //   [7:0] data
    input wire [9:0] data_from_mem,
    input wire [9:0] data_from_sha,
    input wire [9:0] data_from_aes,
    input wire [9:0] data_from_ctrl,

    // global arbiter -> all data local interfaces
    output wire [9:0] data_to_locals,

    // read grants to data local interfaces
    // bit mapping:
    //   [0] mem
    //   [1] sha
    //   [2] aes
    //   [3] ctrl
    output wire [3:0] rdy_rd_grant,
    output wire [3:0] dv_rd_grant,

    // ack local interfaces -> global arbiter
    input wire ack_valid_from_mem,
    input wire ack_valid_from_sha,
    input wire ack_valid_from_aes,
    input wire ack_valid_from_ctrl,

    // global arbiter -> ack local interfaces
    output wire ack_ready_to_mem,
    output wire ack_ready_to_sha,
    output wire ack_ready_to_aes,
    output wire ack_ready_to_ctrl,  
    // ack bus exposed to ctrl
    output wire [2:0] ack_bus_to_ctrl
);

    // local IDs
    // bit mapping:
    //   mem  = 00 -> bit 0
    //   sha  = 01 -> bit 1
    //   aes  = 10 -> bit 2
    //   ctrl = 11 -> bit 3

    localparam [1:0] MEM_ID  = 2'b00;
    localparam [1:0] SHA_ID  = 2'b01;
    localparam [1:0] AES_ID  = 2'b10;
    localparam [1:0] CTRL_ID = 2'b11;

    // internal data bus wires

    wire [7:0] data_on_bus;
    wire       valid_on_bus;
    wire       rdy_to_owner;
    wire [1:0] data_sel;

    // data_sel chooses who is currently driving the shared data bus
    assign data_on_bus = (data_sel == MEM_ID) ? data_from_mem[7:0] : (data_sel == SHA_ID) ? data_from_sha[7:0]  :
    (data_sel == AES_ID) ? data_from_aes[7:0] : (data_sel == CTRL_ID) ? data_from_ctrl[7:0] : 8'h00;

    assign valid_on_bus = (data_sel == MEM_ID) ? data_from_mem[8] : (data_sel == SHA_ID) ? data_from_sha[8] :
    (data_sel == AES_ID) ? data_from_aes[8] : (data_sel == CTRL_ID) ? data_from_ctrl[8] : 1'b0;

    // broadcast shared data bus back to all DATA_LOCAL interfaces
    assign data_to_locals = {rdy_to_owner, valid_on_bus, data_on_bus};

    // internal ack bus wires
    // ack_bus_arbiter uses active-low valid
    // data_bus_ctrl expects active-high valid
    wire       ack_valid_n;
    wire       valid_on_ack;
    wire       ready_on_ack;
    wire [1:0] id_on_ack;
    wire [1:0] winner_source_id;

    assign valid_on_ack = ~ack_valid_n;
    assign ready_on_ack = 1; // forced to 1 since just need to check ack and winner for databus ctrl
    assign id_on_ack    = winner_source_id;

    // broadcast ack bus to ctrl
    assign ack_bus_to_ctrl = {ack_valid_n, winner_source_id};
    // data bus controller
    // controls data_sel, read grants, and ready-to-current-owner

    data_bus_ctrl u_data_bus_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),

        // current shared data bus
        .data_on_bus  (data_on_bus),
        .valid_on_bus (valid_on_bus),

        // ready from modules through DATA_LOCAL interfaces
        .rdy_mem      (data_from_mem[9]),
        .rdy_aes      (data_from_aes[9]),
        .rdy_sha      (data_from_sha[9]),

        // ack bus handshake
        .id_on_ack    (id_on_ack),
        .ready_on_ack (ready_on_ack),
        .valid_on_ack (valid_on_ack),

        // grants and bus owner select
        .rdy_rd_grant (rdy_rd_grant),
        .dv_rd_grant  (dv_rd_grant),
        .data_sel     (data_sel),

        // ready back to current data bus owner
        .rdy_to_owner (rdy_to_owner)
    );

    // ack bus arbiter
    // chooses one ack source and sends winner ID to data_bus_ctrl

    ack_bus_arbiter u_ack_bus_arbiter (
        // ack valid requests from ACK_LOCAL interfaces
        .ack_valid_from_ctrl (ack_valid_from_ctrl),
        .ack_valid_from_aes  (ack_valid_from_aes),
        .ack_valid_from_sha  (ack_valid_from_sha),
        .ack_valid_from_mem  (ack_valid_from_mem),

        // ready back to ACK_LOCAL interfaces
        .ack_ready_to_ctrl   (ack_ready_to_ctrl),
        .ack_ready_to_aes    (ack_ready_to_aes),
        .ack_ready_to_sha    (ack_ready_to_sha),
        .ack_ready_to_mem    (ack_ready_to_mem),

        // shared ack bus result
        .ack_valid_n         (ack_valid_n),
        .winner_source_id    (winner_source_id)
    );

endmodule