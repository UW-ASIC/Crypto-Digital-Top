/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module control_top #(
  parameter ADDRW      = 24,
  parameter OPCODEW    = 2,
  parameter REQ_QDEPTH = 2,
  parameter COMP_QDEPTH = 2
  ) (
    output  wire       miso,
    input   wire       mosi,
    input   wire       clk,
    input   wire       spi_clk,
    input   wire       rst_n,
    input   wire       cs_n,
    input   wire [2:0] ack_in,
    input   wire       bus_ready,

    output reg [7:0]   data_bus_out,
    output reg         data_bus_valid
);

  localparam AES_INSTRW = 3*ADDRW + OPCODEW;

  wire [1:0] curr_mode_top_unused;
  wire [1:0] counter_top_unused;

  wire [OPCODEW-1:0] opcode;
  wire [ADDRW-1:0]   key_addr;
  wire [ADDRW-1:0]   text_addr;
  wire [ADDRW-1:0]   dest_addr;
  wire               req_q_valid;
  wire               aes_queue_ready;

  deserializer #(.ADDRW(ADDRW), .OPCODEW(OPCODEW)) deserializer_inst (
    .clk          (clk),
    .rst_n        (rst_n),
    .spi_clk      (spi_clk),
    .mosi         (mosi),
    .cs_n         (cs_n),
    .aes_ready_in (aes_queue_ready),
    .opcode       (opcode),
    .key_addr     (key_addr),
    .text_addr    (text_addr),
    .dest_addr    (dest_addr),
    .valid_out    (req_q_valid)
  );

  wire [AES_INSTRW-1:0] instr_aes;
  wire                  valid_out_aes;
  wire                  aes_fsm_ready;

  req_queue #(.ADDRW(ADDRW), .OPCODEW(OPCODEW), .QDEPTH(REQ_QDEPTH)) req_queue_inst (
    .clk          (clk),
    .rst_n        (rst_n),
    .valid_in     (req_q_valid),
    .ready_in_aes (aes_fsm_ready),
    .opcode       (opcode),
    .key_addr     (key_addr),
    .text_addr    (text_addr),
    .dest_addr    (dest_addr),
    .instr_aes    (instr_aes),
    .valid_out_aes(valid_out_aes),
    .ready_out_aes(aes_queue_ready)
  );

  wire [ADDRW-1:0] compq_aes_data;
  wire             compq_aes_valid;
  wire             compq_ready_aes;
  wire             aes_arb_req;
  wire             aes_arb_grant;
  wire [ADDRW+7:0] aes_fsm_data;

  aes_fsm #(.ADDRW(ADDRW)) aes_fsm_inst (
    .clk            (clk),
    .rst_n          (rst_n),
    .req_valid      (valid_out_aes),
    .req_data       (instr_aes),
    .ready_req_out  (aes_fsm_ready),
    .compq_ready_in (compq_ready_aes),
    .compq_data_out (compq_aes_data),
    .valid_compq_out(compq_aes_valid),
    .arb_req        (aes_arb_req),
    .arb_grant      (aes_arb_grant),
    .ack_in         (ack_in),
    .data_out       (aes_fsm_data)
  );

  bus_arbiter #(.ADDRW(ADDRW)) bus_arbiter_inst (
    .clk           (clk),
    .rst_n         (rst_n),
    .aes_req       (aes_arb_req),
    .aes_data_in   (aes_fsm_data),
    .bus_ready     (bus_ready),
    .data_out      (data_bus_out),
    .valid_out     (data_bus_valid),
    .aes_grant     (aes_arb_grant),
    .curr_mode_top (curr_mode_top_unused),
    .counter_top   (counter_top_unused)
  );

  wire [ADDRW-1:0] compq_data;
  wire             compq_valid_out;
  wire             compq_ready_in;

  comp_queue #(.ADDRW(ADDRW), .QDEPTH(COMP_QDEPTH)) comp_queue_inst (
    .clk          (clk),
    .rst_n        (rst_n),
    .valid_in_aes (compq_aes_valid),
    .dest_addr_aes(compq_aes_data),
    .ready_out_aes(compq_ready_aes),
    .data_out     (compq_data),
    .valid_out    (compq_valid_out),
    .ready_in     (compq_ready_in)
  );

  serializer #(.ADDRW(ADDRW)) serializer_inst (
    .clk      (clk),
    .rst_n    (rst_n),
    .n_cs     (cs_n),
    .spi_clk  (spi_clk),
    .valid_in (compq_valid_out),
    .addr     (compq_data),
    .miso     (miso),
    .ready_out(compq_ready_in)
  );

  wire _unused = &{counter_top_unused, curr_mode_top_unused};
endmodule
