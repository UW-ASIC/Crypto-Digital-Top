/*
 * Copyright (c) 2024 UWASIC
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_uwasic_crypto (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

// for debug
wire sclk = ui_in[0];
wire cs = ui_in[1];
wire mosi =  ui_in[2];

initial begin
    $dumpfile("p.vcd");
    $dumpvars(0, tt_um_uwasic_crypto);
end

// interconnect wire
// mem
// mem -> data bus
wire [7:0] data_mem_bus;
wire valid_mem_bus;
wire ready_bus_mem;

// data bus -> mem
wire [7:0] data_bus_mem;
wire valid_bus_mem;
wire ready_mem_bus;

// mem -> ack bus
wire [1:0] ack_id_mem_bus;
wire ack_valid_mem_bus;
wire ack_ready_bus_mem;

// sha
// sha -> data bus
wire [7:0] data_sha_bus;
wire valid_sha_bus;
wire ready_bus_sha;

// data bus -> sha
wire [7:0] data_bus_sha;
wire valid_bus_sha;
wire ready_sha_bus;

// sha -> ack bus
wire [1:0] ack_id_sha_bus;
wire ack_valid_sha_bus;
wire ack_ready_bus_sha;

// aes
// aes -> data bus
wire [7:0] data_aes_bus;
wire valid_aes_bus;
wire ready_bus_aes;

// data bus -> aes
wire [7:0] data_bus_aes;
wire valid_bus_aes;
wire ready_aes_bus;

// aes -> ack bus
wire [1:0] ack_id_aes_bus;
wire ack_valid_aes_bus;
wire ack_ready_bus_aes;

// ctrl
// ctrl -> data bus
wire [7:0] data_ctrl_bus;
wire valid_ctrl_bus;
wire ready_bus_ctrl;

// ctrl -> ack bus
wire [1:0] ack_id_ctrl_bus;
wire ack_valid_ctrl_bus;
wire ack_ready_bus_ctrl;

// ack bus -> ctrl
wire [2:0] ack_bus_ctrl;


// unused top-level output pins
assign uo_out[7:3]  = 5'b0;
assign uio_out[7:4] = 4'b0;
assign uio_oe[7:4]  = 4'b0;


interconnect_top u_interconnect_top (
    .clk(clk),
    .rst_n(rst_n),

    // mem -> data bus
    .data_in_mem(data_mem_bus),
    .valid_in_mem(valid_mem_bus),
    .ready_out_mem(ready_bus_mem),

    // data bus -> mem
    .data_out_mem(data_bus_mem),
    .valid_out_mem(valid_bus_mem),
    .ready_in_mem(ready_mem_bus),

    // mem -> ack bus
    .ack_id_in_mem(ack_id_mem_bus),
    .ack_valid_in_mem(ack_valid_mem_bus),
    .ack_ready_out_mem(ack_ready_bus_mem),

    // sha -> data bus
    .data_in_sha(data_sha_bus),
    .valid_in_sha(valid_sha_bus),
    .ready_out_sha(ready_bus_sha),

    // data bus -> sha
    .data_out_sha(data_bus_sha),
    .valid_out_sha(valid_bus_sha),
    .ready_in_sha(ready_sha_bus),

    // sha -> ack bus
    .ack_id_in_sha(ack_id_sha_bus),
    .ack_valid_in_sha(ack_valid_sha_bus),
    .ack_ready_out_sha(ack_ready_bus_sha),

    // aes -> data bus
    .data_in_aes(data_aes_bus),
    .valid_in_aes(valid_aes_bus),
    .ready_out_aes(ready_bus_aes),

    // data bus -> aes
    .data_out_aes(data_bus_aes),
    .valid_out_aes(valid_bus_aes),
    .ready_in_aes(ready_aes_bus),

    // aes -> ack bus
    .ack_id_in_aes(ack_id_aes_bus),
    .ack_valid_in_aes(ack_valid_aes_bus),
    .ack_ready_out_aes(ack_ready_bus_aes),

    // ctrl -> data bus
    .data_in_ctrl(data_ctrl_bus),
    .valid_in_ctrl(valid_ctrl_bus),
    .ready_out_ctrl(ready_bus_ctrl),

    // ctrl -> ack bus
    .ack_id_in_ctrl(ack_id_ctrl_bus),
    .ack_valid_in_ctrl(ack_valid_ctrl_bus),
    .ack_ready_out_ctrl(ack_ready_bus_ctrl),

    // ack bus -> ctrl
    .ack_out_ctrl(ack_bus_ctrl)
);


// sha
sha u_sha (
    .clk(clk),
    .rst_n(rst_n),

    // data bus -> sha
    .data_in(data_bus_sha),
    .ready_in(ready_sha_bus),
    .valid_in(valid_bus_sha),

    // sha -> data bus
    .data_out(data_sha_bus),
    .data_ready(ready_bus_sha),
    .data_valid(valid_sha_bus),

    // sha -> ack bus
    .ack_ready(ack_ready_bus_sha),
    .ack_valid(ack_valid_sha_bus),
    .module_source_id(ack_id_sha_bus),

    // transaction bus
    .opcode(data_bus_sha[1:0]),
    .source_id(data_bus_sha[3:2]),
    .dest_id(data_bus_sha[5:4]),
    .encdec(data_bus_sha[7]),
    .addr(24'b0)
);


// aes
aes_top u_aes_top (
    .clk(clk),
    .rst_n(rst_n),

    // data bus -> aes
    .data_in(data_bus_aes),
    .valid_in(valid_bus_aes),
    .ready_out(ready_aes_bus),

    // aes -> data bus
    .data_out(data_aes_bus),
    .valid_out(valid_aes_bus),
    .ready_in(ready_bus_aes),

    // aes -> ack bus
    .ack_ready(ack_ready_bus_aes),
    .ack_valid(ack_valid_aes_bus),
    .ack_id(ack_id_aes_bus)
);


// mem
mem_top u_mem_top (
    .clk(clk),
    .rst_n(rst_n),

    // mem -> data bus
    .READY(ready_bus_mem),
    .VALID(valid_mem_bus),
    .DATA(data_mem_bus),

    // data bus -> mem
    .READY_IN(ready_mem_bus),
    .VALID_IN(valid_bus_mem),
    .DATA_IN(data_bus_mem),

    // mem -> ack bus
    .ACK_READY(ack_ready_bus_mem),
    .ACK_VALID(ack_valid_mem_bus),
    .MODULE_SOURCE_ID(ack_id_mem_bus),

    // IOs
    .CS(uo_out[2]),
    .SCLK(uo_out[1]),

    .IN0(uio_in[0]),
    .IN1(uio_in[1]),
    .IN2(uio_in[2]),
    .IN3(uio_in[3]),

    .OUT0(uio_out[0]),
    .OUT1(uio_out[1]),
    .OUT2(uio_out[2]),
    .OUT3(uio_out[3]),

    .uio_oe(uio_oe[3:0]),

    // test only
    .err()
);


// ctrl does not send ack packets into ack bus
assign ack_id_ctrl_bus    = 2'b00;
assign ack_valid_ctrl_bus = 1'b0;


// ctrl
control_top u_control_top (
    .miso(uo_out[0]),
    .mosi(ui_in[2]),
    .ena(ena),
    .spi_clk(ui_in[0]),
    .cs_n(ui_in[1]),

    .clk(clk),
    .rst_n(rst_n),

    .ack_in(ack_bus_ctrl),
    .bus_ready(ready_bus_ctrl),

    .data_bus_out(data_ctrl_bus),
    .data_bus_valid(valid_ctrl_bus)
);

endmodule

`default_nettype wire