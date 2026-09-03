module main (
    input wire clk,
    input wire rst_n,
    input wire restart_mic,
    input wire start_measurement,
    input wire mic1_pdm,
    input wire mic2_pdm,
    output wire [11:0] echo_window_index,
    output wire transducer_drive_a,
    output wire transducer_drive_b,
    output wire mic_clk,
    output wire [5:0]  angle_out_horizontal,
    output wire angle_valid_horizontal
);
    wire tick_4mhz;
    wire mic_ready;

    clk_div_10 clock_divider (
        .clk(clk),
        .rst_n(rst_n),
        .tick_4mhz(tick_4mhz)
    );

    echo_angle_detector echo_angle_detector_horizontal (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .start_measurement(start_measurement),
        .mic1_pdm(mic1_pdm),
        .mic2_pdm(mic2_pdm),
        .angle_out(angle_out_horizontal),
        .angle_valid(angle_valid_horizontal),
        .echo_window(echo_window_index)
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
        .restart(restart_mic),
        .mic_clk(mic_clk),
        .mic_ready(mic_ready)
    );

endmodule