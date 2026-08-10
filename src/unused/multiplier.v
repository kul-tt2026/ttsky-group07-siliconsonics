`default_nettype none

module constant_multiplier (
    input wire [15:0] data_in_1,  // Unsigned 16-bit input 1
    input wire [15:0] data_in_2,  // Unsigned 16-bit input 2
    output wire [31:0] data_out   // Unsigned 32-bit output (16-bit * 16-bit)
);
    assign data_out = data_in_1 * data_in_2;

endmodule