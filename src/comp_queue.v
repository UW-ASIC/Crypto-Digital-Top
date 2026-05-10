module comp_queue #(
    parameter ADDRW  = 24,
    parameter QDEPTH = 2
)(
    input  wire clk,
    input  wire rst_n,

    input  wire                 valid_in_aes,
    input  wire [ADDRW-1:0]     dest_addr_aes,
    output reg                  ready_out_aes,

    output reg [ADDRW-1:0]      data_out,
    output reg                  valid_out,
    input  wire                 ready_in
);

    reg [ADDRW-1:0] mem [0:QDEPTH-1];
    localparam integer IDXW   = (QDEPTH <= 1) ? 1 : $clog2(QDEPTH);
    localparam integer COUNTW = (QDEPTH <= 1) ? 1 : $clog2(QDEPTH + 1);
    localparam [IDXW-1:0]   LAST_IDX  = IDXW'(QDEPTH - 1);
    localparam [COUNTW-1:0] COUNT_MAX = QDEPTH;

    function [IDXW-1:0] increment_ptr;
        input [IDXW-1:0] val;
        increment_ptr = (val == LAST_IDX) ? {IDXW{1'b0}} : val + 1'b1;
    endfunction

    reg [IDXW-1:0]   head, tail;
    reg [COUNTW-1:0] count;

    wire full  = (count == COUNT_MAX);
    wire empty = (count == {COUNTW{1'b0}});

    wire do_enq = valid_in_aes && !full;
    wire do_deq = valid_out && ready_in;

    always @(*) ready_out_aes = !full;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head      <= {IDXW{1'b0}};
            tail      <= {IDXW{1'b0}};
            count     <= {COUNTW{1'b0}};
            valid_out <= 0;
            data_out  <= 0;
        end else begin
            if (do_enq) begin
                mem[tail] <= dest_addr_aes;
                tail      <= increment_ptr(tail);
            end

            if (!empty && !valid_out) begin
                data_out  <= mem[head];
                valid_out <= 1;
            end

            if (do_deq) begin
                head      <= increment_ptr(head);
                valid_out <= 0;
            end

            if (do_enq && do_deq)
                count <= count;
            else if (do_enq)
                count <= count + 1;
            else if (do_deq)
                count <= count - 1;
        end
    end

endmodule
