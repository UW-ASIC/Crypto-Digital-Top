`default_nettype none

module interconnect_top (
    input wire clk,
    input wire rst_n,

    // mem -> data bus
    input  wire [7:0] data_in_mem,
    input  wire       valid_in_mem,
    output wire       ready_out_mem,

    // data bus -> mem
    output wire [7:0] data_out_mem,
    output wire       valid_out_mem,
    input  wire       ready_in_mem,

    // mem -> ack bus
    input  wire [1:0] ack_id_in_mem,
    input  wire       ack_valid_in_mem,
    output wire       ack_ready_out_mem,

    // aes -> data bus
    input  wire [7:0] data_in_aes,
    input  wire       valid_in_aes,
    output wire       ready_out_aes,

    // data bus -> aes
    output wire [7:0] data_out_aes,
    output wire       valid_out_aes,
    input  wire       ready_in_aes,

    // aes -> ack bus
    input  wire [1:0] ack_id_in_aes,
    input  wire       ack_valid_in_aes,
    output wire       ack_ready_out_aes,

    // ctrl -> data bus
    input  wire [7:0] data_in_ctrl,
    input  wire       valid_in_ctrl,
    output wire       ready_out_ctrl,

    // ctrl -> ack bus
    input  wire [1:0] ack_id_in_ctrl,
    input  wire       ack_valid_in_ctrl,
    output wire       ack_ready_out_ctrl,
    // ack bus exposed to ctrl
    output wire [2:0] ack_out_ctrl
);

    // packed data bus format: [9]=ready [8]=valid [7:0]=data
    wire [9:0] data_to_locals;

    wire [9:0] data_from_mem_local;
    wire [9:0] data_from_aes_local;
    wire [9:0] data_from_ctrl_local;

    wire [9:0] data_to_mem_local;
    wire [9:0] data_to_aes_local;
    wire [9:0] data_to_ctrl_local;

    // grant wires: [0]=mem [1]=unused [2]=aes [3]=ctrl
    wire [3:0] rdy_rd_grant;
    wire [3:0] dv_rd_grant;

    // mem DATA_LOCAL
    data_bus_module_interface u_mem_data_local (
        .rdy_rd_grant     (rdy_rd_grant[0]),
        .dv_rd_grant      (dv_rd_grant[0]),
        .data_in          (data_to_locals),
        .data_from_module ({ready_in_mem, valid_in_mem, data_in_mem}),
        .data_out         (data_from_mem_local),
        .data_to_module   (data_to_mem_local)
    );

    assign ready_out_mem = data_to_mem_local[9];
    assign valid_out_mem = data_to_mem_local[8];
    assign data_out_mem  = data_to_mem_local[7:0];

    // aes DATA_LOCAL
    data_bus_module_interface u_aes_data_local (
        .rdy_rd_grant     (rdy_rd_grant[2]),
        .dv_rd_grant      (dv_rd_grant[2]),
        .data_in          (data_to_locals),
        .data_from_module ({ready_in_aes, valid_in_aes, data_in_aes}),
        .data_out         (data_from_aes_local),
        .data_to_module   (data_to_aes_local)
    );

    assign ready_out_aes = data_to_aes_local[9];
    assign valid_out_aes = data_to_aes_local[8];
    assign data_out_aes  = data_to_aes_local[7:0];

    // ctrl DATA_LOCAL
    data_bus_module_interface u_ctrl_data_local (
        .rdy_rd_grant     (rdy_rd_grant[3]),
        .dv_rd_grant      (dv_rd_grant[3]),
        .data_in          (data_to_locals),
        .data_from_module ({1'b0, valid_in_ctrl, data_in_ctrl}),
        .data_out         (data_from_ctrl_local),
        .data_to_module   (data_to_ctrl_local)
    );

    assign ready_out_ctrl = data_to_ctrl_local[9];

    // ack local wires
    wire ack_valid_from_mem_local;
    wire ack_valid_from_aes_local;
    wire ack_valid_from_ctrl_local;

    wire ack_ready_to_mem_local;
    wire ack_ready_to_aes_local;
    wire ack_ready_to_ctrl_local;

    wire [1:0] ack_id_from_mem_local;
    wire [1:0] ack_id_from_aes_local;
    wire [1:0] ack_id_from_ctrl_local;

    wire [2:0] ack_bus_to_ctrl;
    assign ack_out_ctrl = ack_bus_to_ctrl;

    // mem ACK_LOCAL
    ack_bus_module_interface u_mem_ack_local (
        .ACK_READY                    (ack_ready_to_mem_local),
        .ACK_READY_TO_MODULE           (ack_ready_out_mem),
        .MODULE_SIDE_ACK_VALID         (ack_valid_in_mem),
        .ACK_VALID                     (ack_valid_from_mem_local),
        .MODULE_SIDE_MODULE_SOURCE_ID  (ack_id_in_mem),
        .MODULE_SOURCE_ID              (ack_id_from_mem_local)
    );

    // aes ACK_LOCAL
    ack_bus_module_interface u_aes_ack_local (
        .ACK_READY                    (ack_ready_to_aes_local),
        .ACK_READY_TO_MODULE           (ack_ready_out_aes),
        .MODULE_SIDE_ACK_VALID         (ack_valid_in_aes),
        .ACK_VALID                     (ack_valid_from_aes_local),
        .MODULE_SIDE_MODULE_SOURCE_ID  (ack_id_in_aes),
        .MODULE_SOURCE_ID              (ack_id_from_aes_local)
    );

    // ctrl ACK_LOCAL
    ack_bus_module_interface u_ctrl_ack_local (
        .ACK_READY                    (ack_ready_to_ctrl_local),
        .ACK_READY_TO_MODULE           (ack_ready_out_ctrl),
        .MODULE_SIDE_ACK_VALID         (ack_valid_in_ctrl),
        .ACK_VALID                     (ack_valid_from_ctrl_local),
        .MODULE_SIDE_MODULE_SOURCE_ID  (ack_id_in_ctrl),
        .MODULE_SOURCE_ID              (ack_id_from_ctrl_local)
    );

    global_arbiter u_global_arbiter (
        .clk   (clk),
        .rst_n (rst_n),

        .data_from_mem  (data_from_mem_local),
        .data_from_aes  (data_from_aes_local),
        .data_from_ctrl (data_from_ctrl_local),

        .data_to_locals (data_to_locals),
        .rdy_rd_grant   (rdy_rd_grant),
        .dv_rd_grant    (dv_rd_grant),

        .ack_valid_from_mem  (ack_valid_from_mem_local),
        .ack_valid_from_aes  (ack_valid_from_aes_local),
        .ack_valid_from_ctrl (ack_valid_from_ctrl_local),

        .ack_ready_to_mem  (ack_ready_to_mem_local),
        .ack_ready_to_aes  (ack_ready_to_aes_local),
        .ack_ready_to_ctrl (ack_ready_to_ctrl_local),

        .ack_bus_to_ctrl (ack_bus_to_ctrl)
    );

    wire _unused_ack_ids = ^{ack_id_from_mem_local, ack_id_from_aes_local,
                              ack_id_from_ctrl_local, data_to_ctrl_local[8:0]};
    wire _unused = &{rdy_rd_grant[1], dv_rd_grant[1]};

endmodule
