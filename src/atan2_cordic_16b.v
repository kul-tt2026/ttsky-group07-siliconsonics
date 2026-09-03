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

script for generation is of the coordinates: arctg_table.py

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

module atan2_cordic_16b (
    input wire clk,
    input wire rst_n,
    input wire signed [15:0] x_in,
    input wire signed [15:0] y_in,
    input wire load_input,
    output wire angle_valid,
    output reg [11:0] angle_out
);
    reg [3:0] iteration_idx;
    reg signed [23:0] x_reg;
    reg signed [23:0] y_reg;
    reg [11:0] angle_table [0:7];

    assign angle_valid = (iteration_idx == 4'd8);

    wire positive_angle = (y_reg[23] == 1'b0);
    wire inverted_rotation = (x_reg[23] == 1'b1);

    initial begin
        angle_table[0] = 12'd512;
        angle_table[1] = 12'd302;
        angle_table[2] = 12'd160;
        angle_table[3] = 12'd81;
        angle_table[4] = 12'd41;
        angle_table[5] = 12'd20;
        angle_table[6] = 12'd10;
        angle_table[7] = 12'd5;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            iteration_idx <= 4'd8;
            x_reg <= 24'd0;
            y_reg <= 24'd0;
            angle_out <= 12'd0;
        end
        else begin
            if (load_input) begin
                x_reg <= {{8{x_in[15]}}, x_in} <<< 8;
                y_reg <= {{8{y_in[15]}}, y_in} <<< 8;
                iteration_idx <= 4'd0;
                angle_out <= x_in[15] ? 12'd2048 : 12'd0;
            end
            else if (y_reg == 0) begin
                iteration_idx <= 4'd8;
            end
            else if (!angle_valid) begin
                iteration_idx <= iteration_idx + 1;

                x_reg <= (positive_angle ~^ !inverted_rotation) ?
                    (x_reg + (y_reg >>> iteration_idx[2:0])) :
                    (x_reg - (y_reg >>> iteration_idx[2:0]));

                y_reg <= (positive_angle ~^ !inverted_rotation) ?
                    (-(x_reg >>> iteration_idx[2:0]) + y_reg) :
                    ((x_reg >>> iteration_idx[2:0]) + y_reg);

                angle_out <= (positive_angle ~^ !inverted_rotation) ?
                    angle_out + angle_table[iteration_idx[2:0]] :
                    angle_out - angle_table[iteration_idx[2:0]];
            end
        end
    end
endmodule
