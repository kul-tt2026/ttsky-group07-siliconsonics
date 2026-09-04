module phase_difference_to_angle (
    input wire clk,
    input wire rst_n,

    input wire [11:0] delta_phase_in,

    output reg [5:0] angle_out, // 64
    output reg invalid_input
);
    wire _unused_pd2a = &{1'b0, clk, rst_n, delta_phase_in[5:0]};

    always @(*) begin
        angle_out    = 6'd0;
        invalid_input = 1'b0;

        case (delta_phase_in[11:6])
            6'd0: angle_out = 6'd0;
            6'd1: angle_out = 6'd0;
            6'd2: angle_out = 6'd1;
            6'd3: angle_out = 6'd1;
            6'd4: angle_out = 6'd2;
            6'd5: angle_out = 6'd2;
            6'd6: angle_out = 6'd3;
            6'd7: angle_out = 6'd3;
            6'd8: angle_out = 6'd4;
            6'd9: angle_out = 6'd4;
            6'd10: angle_out = 6'd5;
            6'd11: angle_out = 6'd5;
            6'd12: angle_out = 6'd6;
            6'd13: angle_out = 6'd6;
            6'd14: angle_out = 6'd7;
            6'd15: angle_out = 6'd7;
            6'd16: angle_out = 6'd8;
            6'd17: angle_out = 6'd9;
            6'd18: angle_out = 6'd10;
            6'd19: angle_out = 6'd10;
            6'd20: angle_out = 6'd11;
            6'd21: angle_out = 6'd12;
            6'd22: angle_out = 6'd14;
            6'd42: angle_out = 6'd50;
            6'd43: angle_out = 6'd52;
            6'd44: angle_out = 6'd53;
            6'd45: angle_out = 6'd54;
            6'd46: angle_out = 6'd54;
            6'd47: angle_out = 6'd55;
            6'd48: angle_out = 6'd56;
            6'd49: angle_out = 6'd57;
            6'd50: angle_out = 6'd57;
            6'd51: angle_out = 6'd58;
            6'd52: angle_out = 6'd58;
            6'd53: angle_out = 6'd59;
            6'd54: angle_out = 6'd59;
            6'd55: angle_out = 6'd60;
            6'd56: angle_out = 6'd60;
            6'd57: angle_out = 6'd61;
            6'd58: angle_out = 6'd61;
            6'd59: angle_out = 6'd62;
            6'd60: angle_out = 6'd62;
            6'd61: angle_out = 6'd63;
            6'd62: angle_out = 6'd63;
            6'd63: angle_out = 6'd0;
            default: begin
                invalid_input = 1'b1;
            end
        endcase
    end
endmodule
