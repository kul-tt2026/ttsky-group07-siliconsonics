module main (
    input wire clk,
    input wire rst_n,
    input wire restart,
    input wire mic_pdm,
    output wire [11:0] echo_window_index,
    output wire echo_found,
    output wire transducer_drive_a,
    output wire transducer_drive_b,
    output wire mic_clk
);
    wire tick_4mhz;
    wire mic_ready;

    clk_div_10 clock_divider (
        .clk(clk),
        .rst_n(rst_n),
        .tick_4mhz(tick_4mhz)
    );

    first_echo_timing echo_timing (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .restart(restart),
        .mic_pdm(mic_pdm),
        .echo_window_index(echo_window_index),
        .echo_found(echo_found)
    );

    transducer_ping_generator transducer_signal_generator (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .restart(restart),
        .drive_a(transducer_drive_a),
        .drive_b(transducer_drive_b)
    );

    ultrasonic_mic_powerup_sequence mic_powerup_signals (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .restart(restart),
        .mic_clk(mic_clk),
        .mic_ready(mic_ready)
    );

endmodule