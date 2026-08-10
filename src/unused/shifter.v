`default_nettype none

module down_shifter (
    input wire [31:0] data_in,     // Unsigned 32-bit input value to be shifted
    input wire [3:0]  shift_amt,   // 4-bit input for the shift amount (0 to 15 bits)
    output wire [31:0] data_out    // Unsigned 32-bit output after shifting
);

    // Logical Right Shift for unsigned numbers
    assign data_out = data_in >> shift_amt;

endmodule