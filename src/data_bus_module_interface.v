module data_bus_module_interface (
    // input from global arbiter
    input wire        rdy_rd_grant,
    input wire        dv_rd_grant,

    // global bus into this local interface
    input wire [9:0]  data_in, // [9]:ready, [8]:valid, [7:0]:data

    // local module drives this into arbiter
    input wire [9:0]  data_from_module,

    // this interface drives into global arbiter
    output reg [9:0]  data_out,

    // this interface drives into module
    output reg [9:0]  data_to_module
);

always @(*) begin
    // module's outgoing data/valid/ready always forwarded to global side
    data_out = data_from_module;

    // ready bit is controlled by ready-read grant
    data_to_module[9] = rdy_rd_grant ? data_in[9] : 1'b0;

    // valid bit is controlled by data/valid-read grant
    data_to_module[8] = dv_rd_grant ? data_in[8] : 1'b0;

    // data can be passed through or zeroed; valid=0 means ignore it anyway
    data_to_module[7:0] = data_in[7:0];
end

endmodule