`default_nettype none
module bus_arbiter #(
    parameter ADDRW = 24
    ) (
    input wire clk,
    input wire rst_n,
    input wire sha_req,
    input wire aes_req,
    input wire [ADDRW+7:0] sha_data_in,
    input wire [ADDRW+7:0] aes_data_in,
    input wire bus_ready,

    output reg [7:0] data_out,
    output reg valid_out, 
    output wire aes_grant,
    output wire sha_grant,
    output wire [1:0] curr_mode_top,
    output wire [1:0] counter_top
);

localparam AES = 2'b01;
localparam SHA = 2'b10;

reg last_serviced; // RR to choose a FSM to service if both simultaneously req bus
reg [1:0] curr_mode; // 00: Inactive, 01: AES, 10: SHA
reg [1:0] counter;
wire [4:0] counter_shifted;

assign curr_mode_top = curr_mode;
assign counter_top = counter;
assign counter_shifted = counter << 3;

always @(*) begin
    case (curr_mode)
        AES: begin
            data_out = aes_data_in[counter_shifted +: 8];
            valid_out = 1'b1;
        end
        SHA: begin
            data_out = sha_data_in[counter_shifted +: 8];
            valid_out = 1'b1;
        end
        default: begin
            data_out = 'x;
            valid_out = 1'b0;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        last_serviced <= 1'b0;
        curr_mode <= 2'b00;
        counter <= 2'b00;
    end else begin
        if (bus_ready) begin
            if (curr_mode != 2'b00) begin
                counter <= counter + 1;
            end else begin
                // Counter should always be 0 when curr_mode == 2'b00
                if (sha_req && aes_req) begin
                    curr_mode <= last_serviced ? 2'b10 : 2'b01;
                end else begin
                    curr_mode <= {sha_req, aes_req};
                end
            end
        end

        if (counter == 2'b11) begin
            if (curr_mode == AES) curr_mode <= (sha_req) ? SHA : 2'b00;
            else if (curr_mode == SHA) curr_mode <= (aes_req) ? AES : 2'b00;
        end

        if (curr_mode == AES) last_serviced <= 1'b1;
        else if (curr_mode == SHA) last_serviced <= 1'b0;
    end
end

assign aes_grant = (curr_mode == AES);
assign sha_grant = (curr_mode == SHA);


endmodule
