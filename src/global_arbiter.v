`default_nettype none

module global_arbiter (
    input wire clk,
    input wire rst_n,

    // packed format: [9]=ready [8]=valid [7:0]=data
    input wire [9:0] data_from_mem,
    input wire [9:0] data_from_aes,
    input wire [9:0] data_from_ctrl,

    output wire [9:0] data_to_locals,

    // bit mapping: [0]=mem [1]=unused [2]=aes [3]=ctrl
    output wire [3:0] rdy_rd_grant,
    output wire [3:0] dv_rd_grant,

    input wire ack_valid_from_mem,
    input wire ack_valid_from_aes,
    input wire ack_valid_from_ctrl,

    output wire ack_ready_to_mem,
    output wire ack_ready_to_aes,
    output wire ack_ready_to_ctrl,
    output wire [2:0] ack_bus_to_ctrl
);

    localparam [1:0] MEM_ID  = 2'b00;
    localparam [1:0] AES_ID  = 2'b10;
    localparam [1:0] CTRL_ID = 2'b11;

    wire [7:0] data_on_bus;
    wire       valid_on_bus;
    wire       rdy_to_owner;
    wire [1:0] data_sel;

    assign data_on_bus  = (data_sel == MEM_ID)  ? data_from_mem[7:0]  :
                          (data_sel == AES_ID)  ? data_from_aes[7:0]  :
                          (data_sel == CTRL_ID) ? data_from_ctrl[7:0] : 8'h00;

    assign valid_on_bus = (data_sel == MEM_ID)  ? data_from_mem[8]  :
                          (data_sel == AES_ID)  ? data_from_aes[8]  :
                          (data_sel == CTRL_ID) ? data_from_ctrl[8] : 1'b0;

    assign data_to_locals = {rdy_to_owner, valid_on_bus, data_on_bus};

    wire       ack_valid_n;
    wire       valid_on_ack;
    wire       ready_on_ack;
    wire [1:0] id_on_ack;
    wire [1:0] winner_source_id;

    assign valid_on_ack = ~ack_valid_n;
    assign ready_on_ack = 1;
    assign id_on_ack    = winner_source_id;

    assign ack_bus_to_ctrl = {valid_on_ack, winner_source_id};

    data_bus_ctrl u_data_bus_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .data_on_bus  (data_on_bus),
        .valid_on_bus (valid_on_bus),
        .rdy_mem      (data_from_mem[9]),
        .rdy_aes      (data_from_aes[9]),
        .id_on_ack    (id_on_ack),
        .ready_on_ack (ready_on_ack),
        .valid_on_ack (valid_on_ack),
        .rdy_rd_grant (rdy_rd_grant),
        .dv_rd_grant  (dv_rd_grant),
        .data_sel     (data_sel),
        .rdy_to_owner (rdy_to_owner)
    );

    ack_bus_arbiter u_ack_bus_arbiter (
        .ack_valid_from_ctrl (ack_valid_from_ctrl),
        .ack_valid_from_aes  (ack_valid_from_aes),
        .ack_valid_from_mem  (ack_valid_from_mem),
        .ack_ready_to_ctrl   (ack_ready_to_ctrl),
        .ack_ready_to_aes    (ack_ready_to_aes),
        .ack_ready_to_mem    (ack_ready_to_mem),
        .ack_valid_n         (ack_valid_n),
        .winner_source_id    (winner_source_id)
    );

    wire _unused = &{data_from_ctrl[9]};
endmodule
