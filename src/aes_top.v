`default_nettype none
// unfortunately
module aes_top (
    input  wire clk,
    input  wire rst_n,

    input  wire [7:0] data_in,
    input  wire       valid_in,
    output wire       ready_out,

    output wire [7:0] data_out,
    output wire       valid_out,
    input  wire       ready_in,

    input  wire       ack_ready,
    output wire       ack_valid,
    output wire [1:0] ack_id
);

assign ready_out = 1'b1;
assign data_out = 8'b0;
assign valid_out = 1'b0;
assign ack_valid = 1'b0;
assign ack_id = 2'b10;

endmodule