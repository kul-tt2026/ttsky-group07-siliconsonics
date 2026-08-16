 // Z1 * (Z2*) = (r1 + r2) * e^(i(theta1 - theta2)) => angle with x-axis == delta_phi
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

// atan2(I, Q) from the complex product -> delta phi
// arctg table:
/*
arctg(1) = pi/4
arctg(1/2) = 0.463648
arctg(1/4) = 0.244979
arctg(1/8) = 0.124355
arctg(1/16) = 0.062419
arctg(1/32) = 0.03124
arctg(1/64) = 0.015624
arctg(1/128) = 0.007812

in binary. script for generation is: fixed_point_arctg_table
11001001
01110111
00111111
00100000
00010000
00001000
00000100
00000010

rotation matrix:

A = [
    cos(theta)  -sin(theta);
    sin(theta)  cos(theta)
] = cos(theta) * [
    1           -tan(theta);
    tan(theta)  1
]

=> cos(theta) is omitted as it's not necessary
x_i = x_(i-1)           -/+ y_(i-1) * tan(t)
y_i = x_(i-1) * tan(t)  +/- y_(i-1)

*/
module atan2_cordic (
    input wire clk,
    input wire rst_n,

    // (x,y) vector to calculate angle for
    input wire signed [7:0] x_in, // signed int, has to fit I
    input wire signed [7:0] y_in, // signed int, has to fit Q
    input wire load_input, // HI when x/y should be updated and process should be started

    output wire angle_valid,
    output reg signed [8:0] angle_out // fixed point, angle_out[8] -> -2, angle_out[7] -> 1,  angle_out[6] -> 1/2
);
    reg [3:0] iteration_idx; // 0->9 (0 15): 0->7 - iteration

    reg signed [15:0] x_reg;
    reg signed [15:0] y_reg;

    reg [8:0] angle_table [0:7];

    assign angle_valid = (iteration_idx == 4'd8);

    wire positive_angle = (y_reg[$high(y_reg)] == 1'b0);

    // angles corresponding to the iteration
    initial begin
        angle_table[0] = 9'b001100101;
        angle_table[1] = 9'b000111011;
        angle_table[2] = 9'b000011111;
        angle_table[3] = 9'b000010000;
        angle_table[4] = 9'b000001000;
        angle_table[5] = 9'b000000100;
        angle_table[6] = 9'b000000010;
        angle_table[7] = 9'b000000001;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            iteration_idx <= 4'd8;
            x_reg <= '0;
            y_reg <= '0;
            angle_out  <= '0;
        end
        else begin
            if (load_input) begin
                // if coordinates are in 2nd or 3rd quadrant: move to 1st or 4th
                x_reg[15:8] <= x_in[$high(x_in)] ? -x_in : x_in;
                y_reg[15:8] <= x_in[$high(x_in)] ? -y_in : y_in;

                x_reg[7:0] <= '0;
                y_reg[7:0] <= '0;

                iteration_idx <= '0; // restarts process
                angle_out  <= '0;
            end 
            else if (y_reg == 0) begin
                iteration_idx <= 4'd8; // finished
            end 

            else if (!angle_valid) begin // last iteration not reached yet
                iteration_idx <= iteration_idx + 1;

                /*
                    x_i = x_(i-1)           -/+ y_(i-1) * tan(t)
                    y_i = x_(i-1) * tan(t)  +/- y_(i-1)
                */

                x_reg <= positive_angle ?
                    (x_reg + (y_reg >>> iteration_idx)) : 
                    (x_reg - (y_reg >>> iteration_idx));

                y_reg <= positive_angle ?
                    (-(x_reg >>> iteration_idx)  + y_reg) : 
                    ((x_reg >>> iteration_idx)   + y_reg);

                angle_out <= positive_angle ?
                    angle_out + angle_table[iteration_idx[2:0]] : // iteration_idx stays within 0 7 while iterating (3 bits). 8 means the cordic module is finished
                    angle_out - angle_table[iteration_idx[2:0]];
            end
        end
    end

endmodule

// arcsin(delta_phi * v / (2*pi*f*d)) = theta
module angle_calculation (
    input wire signed [15:0] delta_phi,
    output wire signed [15:0] angle_out
);

endmodule