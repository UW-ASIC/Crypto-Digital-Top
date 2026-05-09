/*List of Source IDs
  MEM: 00; SHA: 01; AES: 10; CTRL: 11
*/
module ack_bus_arbiter (
    // inputs from modules
    // "1" indicates that source module succeeds in sending its last bit, and it asserts its ack signal
    input wire ack_valid_from_ctrl,
    input wire ack_valid_from_aes,
    // input wire ack_valid_from_sha,
    input wire ack_valid_from_mem,
    // input wire [7:0] module_source_ids,        // the id of the source modules sending ack, 2 bits/module, {2'b11, 2'b10, 2'b01, 2'b00}
    
    // output to modules
    // send the arbitration result to the module, "1" indicates that ack_bus is ready, the module can stop asserting ack
    output reg ack_ready_to_ctrl,
    output reg ack_ready_to_aes,
    // output reg ack_ready_to_sha,
    output reg ack_ready_to_mem,

    // ack bus wires (open drain)
    output reg       ack_valid_n,              // active-low: 0 -> some module is asserting its ack signal in this cycle
    output reg [1:0] winner_source_id         // source ID of the winner of the arbitration
);

always @(*) begin 
    // Check the ack_valid signal for all modules to see if they are asserting ack signal
    // Choose the module with highest priority as the winner
    // The following is implemented with priority "CTRL > AES > SHA > MEM" in mind, but can be changed later.

    //default values
    // {ack_ready_to_ctrl, ack_ready_to_aes, ack_ready_to_sha, ack_ready_to_mem} = 4'b0;
    {ack_ready_to_ctrl, ack_ready_to_aes, ack_ready_to_mem} = 3'b0;
    ack_valid_n = 1'b1;
    winner_source_id = 2'b11;   //CTRL has default ownship of the bus

    if (ack_valid_from_ctrl == 1'b1) begin
      //CTRL module is asserting ack
      // {ack_ready_to_ctrl, ack_ready_to_aes, ack_ready_to_sha, ack_ready_to_mem} = 4'b1000;
      {ack_ready_to_ctrl, ack_ready_to_aes, ack_ready_to_mem} = 3'b100;
      ack_valid_n = 1'b0;
      winner_source_id = 2'b11;
    end

    else if (ack_valid_from_aes == 1'b1) begin
      //AES module is asserting ack
      // {ack_ready_to_ctrl, ack_ready_to_aes, ack_ready_to_sha, ack_ready_to_mem} = 4'b0100;
      {ack_ready_to_ctrl, ack_ready_to_aes, ack_ready_to_mem} = 3'b010;
      ack_valid_n = 1'b0;
      winner_source_id = 2'b10;
    end

    // else if (ack_valid_from_sha == 1'b1) begin
    //   //SHA module is asserting ack
    //   {ack_ready_to_ctrl, ack_ready_to_aes, ack_ready_to_sha, ack_ready_to_mem} = 4'b0010;
    //   ack_valid_n = 1'b0;
    //   winner_source_id = 2'b01;
    // end

    else if (ack_valid_from_mem == 1'b1) begin
      //MEM module is asserting ack
      // {ack_ready_to_ctrl, ack_ready_to_aes, ack_ready_to_sha, ack_ready_to_mem} = 4'b0001;
      {ack_ready_to_ctrl, ack_ready_to_aes, ack_ready_to_mem} = 3'b001;
      ack_valid_n = 1'b0;
      winner_source_id = 2'b00;
    end
end

endmodule