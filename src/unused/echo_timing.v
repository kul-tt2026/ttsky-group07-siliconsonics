// Detects first echo by thresholding |I|+|Q| from the I/Q demodulator
// when |I| + |Q| >= threshold: echo_found turns HI and echo_window_index can be read
module first_echo_timing (
    input wire clk,
    input wire tick_4mhz, // 4MHz 10% duty cycle
    input wire rst_n,
    input wire start_measurement, // start
    input wire mic_pdm, // mic pdm signal @ 4MHz

    output reg [11:0] echo_window_index, // window index where |I| + |Q| went over a set threshold
    output reg echo_found // when |I| + |Q| go over the threshold this is set to HI, meaning echo_window_index can be read
);
    wire iq_valid;

    wire [11:0] window_counter;

    wire signed [7:0] I;
    wire signed [7:0] Q;

    wire [7:0] abs_I1 = I[7] ? -I : I;
    wire [7:0] abs_Q1 = Q[7] ? -Q : Q;
    wire [7:0] sig_strength = abs_I1 + abs_Q1; // abs(I) + abs(Q), I and Q always within [-100, 100] -> 8 bits

    windowed_iq_demodulator mic_windowed_iq_demodulator (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .start_measurement(start_measurement),
        .mic_pdm(mic_pdm),
        .I(I),
        .Q(Q),
        .iq_valid(iq_valid),
        .window_counter(window_counter)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            echo_window_index <= 12'd0;
            echo_found <= 1'b1;
        end
        else begin
            if (start_measurement) begin
                echo_window_index <= 12'd0;
                echo_found <= 1'b0;
            end
            else if (tick_4mhz && iq_valid && !echo_found) begin
                if (sig_strength >= 8'd16 && window_counter >= 12'd64) begin // 16: empirical noise/echo threshold, 64: empirical echo_end threshold
                    echo_window_index <= window_counter;
                    echo_found <= 1'b1;
                end
            end
        end
    end

endmodule

/*
2 demodulators, 1 for each mic

*/
module echo_angle_detector (
    input wire clk,
    input wire rst_n,
    input wire tick_4mhz, // 4 MHz 10% duty pulse
    input wire start_measurement,
    input wire mic1_pdm,
    input wire mic2_pdm,

    output reg [5:0] angle_out, // from your phase_difference_to_angle table
    output reg angle_valid, // pulse when angle_out is fresh
    output reg [11:0] echo_window, // center window of detected echo
    output reg echo_found
);

    localparam THRESHOLD = 9'd7; // |I|+|Q| threshold
    localparam MIN_WIDTH = 4'd5; // minimum echo length
    localparam BLANK = 7'd64; // first BLANK ignored windows (direct transmitter -> mic filter)

    localparam IDLE = 3'd0;
    localparam ACCUM = 3'd1;
    localparam ATAN2_M1 = 3'd2;
    localparam ATAN2_M2 = 3'd3;
    localparam CALC = 3'd4;

    reg [2:0] state;

    wire iq1_valid, iq2_valid;
    wire signed [7:0] I1, Q1, I2, Q2;
    wire [11:0] win_cnt1, win_cnt2;

    windowed_iq_demodulator demod1 (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .start_measurement(start_measurement),
        .mic_pdm(mic1_pdm),
        .I(I1),
        .Q(Q1),
        .iq_valid(iq1_valid),
        .window_counter(win_cnt1)
    );

    windowed_iq_demodulator demod2 (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .start_measurement(start_measurement),
        .mic_pdm(mic2_pdm),
        .I(I2),
        .Q(Q2),
        .iq_valid(iq2_valid),
        .window_counter(win_cnt2)
    );

    wire [11:0] window_counter = win_cnt1; // win_cnt1 and win_cnt2 are identical
    wire _unused_wc2 = &{1'b0, win_cnt2};

    wire [7:0] abs_I1 = I1[7] ? -I1 : I1;
    wire [7:0] abs_Q1 = Q1[7] ? -Q1 : Q1;
    wire [7:0] abs_I2 = I2[7] ? -I2 : I2;
    wire [7:0] abs_Q2 = Q2[7] ? -Q2 : Q2;
    wire [8:0] sig1 = abs_I1 + abs_Q1;   // 0->200
    wire [8:0] sig2 = abs_I2 + abs_Q2; // 0->200

    reg signed [15:0] acc_I1, acc_Q1;
    reg signed [15:0] acc_I2, acc_Q2;
    reg [11:0] accum_cnt;
    reg [11:0] echo_start;

    reg signed [15:0] cordic_x, cordic_y;
    reg cordic_load;
    wire cordic_valid;
    wire [11:0] cordic_angle;

    atan2_cordic_16b cordic (
        .clk(clk),
        .rst_n(rst_n),
        .x_in(cordic_x),
        .y_in(cordic_y),
        .load_input(cordic_load),
        .angle_valid(cordic_valid),
        .angle_out(cordic_angle)
    );

    reg [11:0] phase1;

    wire [11:0] delta_phase = cordic_angle - phase1; // when 2nd cordic run is finished it will be correct
    wire [5:0] table_angle;
    wire table_invalid;

    phase_difference_to_angle angle_lut (
        .clk(clk),
        .rst_n(rst_n),
        .delta_phase_in(delta_phase),
        .angle_out(table_angle),
        .invalid_input(table_invalid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            acc_I1 <= 16'd0;
            acc_Q1 <= 16'd0;
            acc_I2 <= 16'd0;
            acc_Q2 <= 16'd0;
            accum_cnt <= 12'd0;
            cordic_load <= 1'b0;
            angle_valid <= 1'b0;
            angle_out <= 6'd0;
            echo_found <= 1'b0;
            echo_window <= 12'd0;
            phase1 <= 12'd0;
            echo_start <= 12'd0;
            cordic_x <= 16'd0;
            cordic_y <= 16'd0;
        end
        else begin
            angle_valid <= 1'b0;
            cordic_load <= 1'b0;

            case (state)
                IDLE: begin
                    if (start_measurement) begin
                        acc_I1 <= 16'd0;
                        acc_Q1 <= 16'd0;
                        acc_I2 <= 16'd0;
                        acc_Q2 <= 16'd0;
                        accum_cnt <= 12'd0;
                        echo_found <= 1'b0;
                        echo_start <= 12'd0;
                        cordic_x <= 16'd0;
                        cordic_y <= 16'd0;
                        state <= ACCUM;
                    end
                end
                ACCUM: begin // acummulate I/Q over multiple windows
                    if (iq1_valid && iq2_valid && tick_4mhz) begin
                        if (sig1 >= THRESHOLD && sig2 >= THRESHOLD // past first gate AND both signals above threshold -> accumulate
                            && window_counter >= {{5{1'b0}}, BLANK}) begin

                            if (accum_cnt == 12'd0) begin
                                echo_start <= window_counter;
                            end

                            acc_I1 <= acc_I1 + {{8{I1[7]}}, I1};
                            acc_Q1 <= acc_Q1 + {{8{Q1[7]}}, Q1};
                            acc_I2 <= acc_I2 + {{8{I2[7]}}, I2};
                            acc_Q2 <= acc_Q2 + {{8{Q2[7]}}, Q2};

                            accum_cnt <= accum_cnt + 1;
                        end
                        else if (accum_cnt >= {{8{1'b0}}, MIN_WIDTH}) begin // proceed to the next state if window is long enough AND threshold isn't crossed anymore
                            cordic_x <= acc_I1;
                            cordic_y <= acc_Q1;
                            cordic_load <= 1'b1;
                            state <= ATAN2_M1;
                        end
                        else if (accum_cnt > 12'd0) begin // there has been accumulation, but it stopped and the total window isnt't long enough
                            acc_I1 <= 16'd0;
                            acc_Q1 <= 16'd0;
                            acc_I2 <= 16'd0;
                            acc_Q2 <= 16'd0;
                            accum_cnt <= 12'd0;
                        end
                    end
                end
                ATAN2_M1: begin // find phase 1
                    if (cordic_valid && !(cordic_load)) begin
                        phase1 <= cordic_angle;
                        cordic_x <= acc_I2;
                        cordic_y <= acc_Q2;
                        cordic_load <= 1'b1;
                        state <= ATAN2_M2;
                    end
                end
                ATAN2_M2: begin // find phase 2
                    if (cordic_valid && !(cordic_load)) begin
                        // delta_phase = cordic_angle - phase1 (mod 4096)
                        state <= CALC;
                    end
                end
                CALC: begin // calculate origin angle
                    angle_out <= table_angle; // table_angle is the angle calculated from delta_phase
                    angle_valid <= ~table_invalid;
                    echo_found  <= ~table_invalid;
                    echo_window <= echo_start; // echo start, alternative:| + (accum_cnt >> 1);  // center of echo

                    // Reset for the next echo
                    acc_I1 <= 16'd0;
                    acc_Q1 <= 16'd0;
                    acc_I2 <= 16'd0;
                    acc_Q2 <= 16'd0;
                    accum_cnt <= 12'd0;
                    state <= ACCUM;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule