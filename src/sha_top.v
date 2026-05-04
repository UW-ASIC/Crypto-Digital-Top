module sha (
    input wire clk,
    input wire rst_n,

    // DATA BUS
    input  wire [7:0] data_in,
    output wire       ready_in,
    input  wire       valid_in,
    output wire [7:0] data_out,
    input  wire       data_ready,
    output wire       data_valid,

    // ACK BUS
    input  wire       ack_ready,
    output wire       ack_valid,
    output wire [1:0] module_source_id
);


    assign ready_in = 1'b0;
    assign data_out = 8'b0;
    assign data_valid = 1'b0;

    assign ack_valid = 1'b0;
    assign module_source_id = 2'b00;

    wire _unused = &{
        1'b0,
        clk,
        rst_n,
        data_in,
        valid_in,
        data_ready,
        ack_ready
    };

endmodule