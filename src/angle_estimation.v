module complex_iq_complex_product (
    input wire signed [7:0] I1,
    input wire signed [7:0] Q1,
    input wire signed [7:0] I2,
    input wire signed [7:0] Q2,
    output wire signed [15:0] I_out,
    output wire signed [15:0] Q_out
);
    assign I_out = (I1 * I2) - (Q1 * Q2);
    assign Q_out = (I1 * Q2) + (Q1 * I2);
endmodule


module arctg_cordic (
    input wire signed [15:0] I_in,
    input wire signed [15:0] Q_in,
    output reg signed [15:0] angle_out
);


endmodule


module angle_calculation (
    input wire signed [15:0] delta_phi,
    output wire signed [15:0] angle_out
);

endmodule