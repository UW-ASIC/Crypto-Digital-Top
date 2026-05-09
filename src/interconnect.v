`default_nettype none

module interconnect_top (
    input wire clk,
    input wire rst_n,

    // mem

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

    // shs

    // sha -> data bus
    // input  wire [7:0] data_in_sha,
    // input  wire       valid_in_sha,
    // output wire       ready_out_sha,

    // // data bus -> sha
    // output wire [7:0] data_out_sha,
    // output wire       valid_out_sha,
    // input  wire       ready_in_sha,

    // // sha -> ack bus
    // input  wire [1:0] ack_id_in_sha,
    // input  wire       ack_valid_in_sha,
    // output wire       ack_ready_out_sha,

    // aes

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

    // ctrl

    // ctrl -> data bus
    // ctrl owns the bus by default and sends opcode/address bytes
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

    // packed data bus format:
    // [9]   ready
    // [8]   valid
    // [7:0] data
    wire [9:0] data_to_locals;

    wire [9:0] data_from_mem_local;
    // wire [9:0] data_from_sha_local;
    wire [9:0] data_from_aes_local;
    wire [9:0] data_from_ctrl_local;

    wire [9:0] data_to_mem_local;
    // wire [9:0] data_to_sha_local;
    wire [9:0] data_to_aes_local;
    wire [9:0] data_to_ctrl_local;


    // grant wires from global arbiter core
    // bit mapping:
    //   [0] mem
    //   [1] sha
    //   [2] aes
    //   [3] ctrl
    wire [3:0] rdy_rd_grant;
    wire [3:0] dv_rd_grant;



    // ctrl does not expose dv_rd_grant_ctrl because ctrl does not read data/valid

    // mem DATA_LOCAL
    data_bus_module_interface u_mem_data_local (
        .rdy_rd_grant     (rdy_rd_grant[0]),
        .dv_rd_grant      (dv_rd_grant[0]),

        // from GLOBAL_ARB to local interface
        .data_in          (data_to_locals),

        // from MEM module to local interface
        .data_from_module ({ready_in_mem, valid_in_mem, data_in_mem}),

        // from local interface to GLOBAL_ARB
        .data_out         (data_from_mem_local),

        // from local interface to MEM module
        .data_to_module   (data_to_mem_local)
    );

    assign ready_out_mem = data_to_mem_local[9];
    assign valid_out_mem = data_to_mem_local[8];
    assign data_out_mem  = data_to_mem_local[7:0];

    // sha DATA_LOCAL
    // data_bus_module_interface u_sha_data_local (
    //     .rdy_rd_grant     (rdy_rd_grant[1]),
    //     .dv_rd_grant      (dv_rd_grant[1]),

    //     // from GLOBAL_ARB to local interface
    //     .data_in          (data_to_locals),

    //     // from SHA module to local interface
    //     .data_from_module ({ready_in_sha, valid_in_sha, data_in_sha}),

    //     // from local interface to GLOBAL_ARB
    //     .data_out         (data_from_sha_local),

    //     // from local interface to SHA module
    //     .data_to_module   (data_to_sha_local)
    // );

    // assign ready_out_sha = data_to_sha_local[9];
    // assign valid_out_sha = data_to_sha_local[8];
    // assign data_out_sha  = data_to_sha_local[7:0];

    // aes DATA_LOCAL
    data_bus_module_interface u_aes_data_local (
        .rdy_rd_grant     (rdy_rd_grant[2]),
        .dv_rd_grant      (dv_rd_grant[2]),

        // from GLOBAL_ARB to local interface
        .data_in          (data_to_locals),

        // from AES module to local interface
        .data_from_module ({ready_in_aes, valid_in_aes, data_in_aes}),

        // from local interface to GLOBAL_ARB
        .data_out         (data_from_aes_local),

        // from local interface to AES module
        .data_to_module   (data_to_aes_local)
    );

    assign ready_out_aes = data_to_aes_local[9];
    assign valid_out_aes = data_to_aes_local[8];
    assign data_out_aes  = data_to_aes_local[7:0];


    // ctrl DATA_LOCAL
    // ctrl sends opcode/address bytes and only reads ready
    data_bus_module_interface u_ctrl_data_local (
        .rdy_rd_grant     (rdy_rd_grant[3]),
        .dv_rd_grant      (dv_rd_grant[3]),

        // from GLOBAL_ARB to local interface
        .data_in          (data_to_locals),

        // ctrl does not provide a ready input as a receiver
        // ctrl only drives valid/data and reads ready_out_ctrl
        .data_from_module ({1'b0, valid_in_ctrl, data_in_ctrl}),

        // from local interface to GLOBAL_ARB
        .data_out         (data_from_ctrl_local),

        // from local interface to CTRL module
        .data_to_module   (data_to_ctrl_local)
    );

    assign ready_out_ctrl = data_to_ctrl_local[9];


    // ack local interface wires
    wire ack_valid_from_mem_local;
    // wire ack_valid_from_sha_local;
    wire ack_valid_from_aes_local;
    wire ack_valid_from_ctrl_local;

    wire ack_ready_to_mem_local;
    // wire ack_ready_to_sha_local;
    wire ack_ready_to_aes_local;
    wire ack_ready_to_ctrl_local;

    wire [1:0] ack_id_from_mem_local;
    // wire [1:0] ack_id_from_sha_local;
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

    // sha ACK_LOCAL
    // ack_bus_module_interface u_sha_ack_local (
    //     .ACK_READY                    (ack_ready_to_sha_local),
    //     .ACK_READY_TO_MODULE           (ack_ready_out_sha),

    //     .MODULE_SIDE_ACK_VALID         (ack_valid_in_sha),
    //     .ACK_VALID                     (ack_valid_from_sha_local),

    //     .MODULE_SIDE_MODULE_SOURCE_ID  (ack_id_in_sha),
    //     .MODULE_SOURCE_ID              (ack_id_from_sha_local)
    // );


    // aes ACK
    ack_bus_module_interface u_aes_ack_local (
        .ACK_READY                    (ack_ready_to_aes_local),
        .ACK_READY_TO_MODULE           (ack_ready_out_aes),

        .MODULE_SIDE_ACK_VALID         (ack_valid_in_aes),
        .ACK_VALID                     (ack_valid_from_aes_local),

        .MODULE_SIDE_MODULE_SOURCE_ID  (ack_id_in_aes),
        .MODULE_SOURCE_ID              (ack_id_from_aes_local)
    );


    // ctrl ACK
    ack_bus_module_interface u_ctrl_ack_local (
        .ACK_READY                    (ack_ready_to_ctrl_local),
        .ACK_READY_TO_MODULE           (ack_ready_out_ctrl),

        .MODULE_SIDE_ACK_VALID         (ack_valid_in_ctrl),
        .ACK_VALID                     (ack_valid_from_ctrl_local),

        .MODULE_SIDE_MODULE_SOURCE_ID  (ack_id_in_ctrl),
        .MODULE_SOURCE_ID              (ack_id_from_ctrl_local)
    );

    // contains data_bus_ctrl + ack_bus_arbiter
    global_arbiter u_global_arbiter (
        .clk   (clk),
        .rst_n (rst_n),

        // DATA_LOCALs -> GLOBAL_ARB
        .data_from_mem  (data_from_mem_local),
        // .data_from_sha  (data_from_sha_local),
        .data_from_aes  (data_from_aes_local),
        .data_from_ctrl (data_from_ctrl_local),

        // GLOBAL_ARB -> DATA_LOCALs
        .data_to_locals (data_to_locals),

        // grants to DATA_LOCALs
        .rdy_rd_grant   (rdy_rd_grant),
        .dv_rd_grant    (dv_rd_grant),

        // ACK_LOCALs -> GLOBAL_ARB
        .ack_valid_from_mem  (ack_valid_from_mem_local),
        // .ack_valid_from_sha  (ack_valid_from_sha_local),
        .ack_valid_from_aes  (ack_valid_from_aes_local),
        .ack_valid_from_ctrl (ack_valid_from_ctrl_local),

        // GLOBAL_ARB -> ACK_LOCALs
        .ack_ready_to_mem  (ack_ready_to_mem_local),
        // .ack_ready_to_sha  (ack_ready_to_sha_local),
        .ack_ready_to_aes  (ack_ready_to_aes_local),
        .ack_ready_to_ctrl (ack_ready_to_ctrl_local),

        .ack_bus_to_ctrl (ack_bus_to_ctrl)
    );


    // unused ack source id wires
    wire _unused_ack_ids;
    // assign _unused_ack_ids = ^{ ack_id_from_mem_local, ack_id_from_sha_local, ack_id_from_aes_local, 
    assign _unused_ack_ids = ^{ ack_id_from_mem_local, ack_id_from_aes_local, 
    ack_id_from_ctrl_local, data_to_ctrl_local[8:0]
    };
    wire _unused = {rdy_rd_grant[1], dv_rd_grant[1]};

endmodule