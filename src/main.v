module main (
    input wire clk,
    input wire rst_n,
    input wire restart_mic,
    input wire start_measurement,
    input wire mic_pdm,
    output wire [15:0] echo_window_index,
    output wire valid_out,
    output wire transducer_drive_a,
    output wire transducer_drive_b,
    output wire mic_clk
);
    wire tick_4mhz;
    wire mic_ready;
    wire echo_found;
    wire [8:0] distance_out;

    clk_div_10 clock_divider (
        .clk(clk),
        .rst_n(rst_n),
        .tick_4mhz(tick_4mhz)
    );

    first_echo_timing echo_timing (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .start_measurement(start_measurement),
        .mic_pdm(mic_pdm),
        .echo_window_index(echo_window_index),
        .echo_found(echo_found)
    );

    transducer_ping_generator transducer_signal_generator (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .start_measurement(start_measurement),
        .drive_a(transducer_drive_a),
        .drive_b(transducer_drive_b)
    );

    ultrasonic_mic_powerup_sequence mic_powerup_signals (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .restart(restart_mic), // mic is not supposed to restart for each pulse
        .mic_clk(mic_clk),
        .mic_ready(mic_ready)
    );

    distance_calculator calc_inst (
        .clk(clk),
        .rst_n(rst_n),
        .expected_window(echo_window_index),
        .valid_in(echo_found),
        .distance_out(distance_out),
        .valid_out(valid_out)
    );

endmodule