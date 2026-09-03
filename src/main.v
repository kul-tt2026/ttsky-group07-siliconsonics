module main #(
    parameter UART_CLKS_PER_BIT  = 347,          // 40 MHz / 115200
    parameter AUTO_PERIOD_TICKS  = 22'd4000000,  // 1 s
    parameter LOCKOUT_TICKS      = 22'd1600000,  // 400 ms
    parameter MEAS_TICKS         = 22'd409600    // 102.4 ms
) (
    input  wire        clk,
    input  wire        rst_n,

    // Pins in
    input  wire        start_measurement,   // rising edge = one ping
    input  wire        auto_enable,         // level, ORed with UART 'A'
    input  wire        mic1_pdm,
    input  wire        mic2_pdm,
    input  wire        restart_mic,
    input  wire        uart_rx,

    // Pins out
    output wire [11:0] echo_window_index,
    output wire [5:0]  angle_out_horizontal,
    output wire        transducer_drive_a,
    output wire        transducer_drive_b,
    output wire        mic_clk,
    output wire        uart_tx,

    // Status
    output wire        mic_ready,
    output wire        auto_mode,
    output wire        busy,
    output wire        result_ready
);
    wire tick_4mhz;
    wire start_pulse;
    wire angle_valid;

    clk_div_10 clock_divider (
        .clk       (clk),
        .rst_n     (rst_n),
        .tick_4mhz (tick_4mhz)
    );

    ultrasonic_mic_powerup_sequence mic_powerup (
        .clk       (clk),
        .tick_4mhz (tick_4mhz),
        .rst_n     (rst_n),
        .restart   (restart_mic),
        .mic_clk   (mic_clk),
        .mic_ready (mic_ready)
    );

    // ---- UART ----
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart_receiver (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (uart_rx),
        .data  (rx_data),
        .valid (rx_valid)
    );

    wire [7:0] fifo_wr_data, fifo_rd_data;
    wire       fifo_wr_en, fifo_full, fifo_empty;
    wire       tx_ready;

    byte_fifo tx_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (fifo_wr_en),
        .wr_data (fifo_wr_data),
        .rd_en   (~fifo_empty & tx_ready),
        .rd_data (fifo_rd_data),
        .full    (fifo_full),
        .empty   (fifo_empty)
    );

    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) uart_transmitter (
        .clk   (clk),
        .rst_n (rst_n),
        .data  (fifo_rd_data),
        .valid (~fifo_empty),
        .ready (tx_ready),
        .tx    (uart_tx)
    );

    // ---- Controller: decides when a ping may fire, speaks the protocol ----
    measurement_controller #(
        .AUTO_PERIOD_TICKS (AUTO_PERIOD_TICKS),
        .LOCKOUT_TICKS     (LOCKOUT_TICKS),
        .MEAS_TICKS        (MEAS_TICKS)
    ) controller (
        .clk          (clk),
        .rst_n        (rst_n),
        .tick_4mhz    (tick_4mhz),
        .mic_ready    (mic_ready),
        .ext_start    (start_measurement),
        .ext_auto     (auto_enable),
        .angle_valid  (angle_valid),
        .echo_window  (echo_window_index),
        .angle_out    (angle_out_horizontal),
        .rx_data      (rx_data),
        .rx_valid     (rx_valid),
        .tx_fifo_full (fifo_full),
        .tx_data      (fifo_wr_data),
        .tx_push      (fifo_wr_en),
        .start_pulse  (start_pulse),
        .auto_mode    (auto_mode),
        .busy         (busy),
        .result_ready (result_ready)
    );

    // ---- Signal chain, now driven by the gated start pulse ----
    wire echo_found_unused;

    echo_angle_detector echo_detector (
        .clk               (clk),
        .rst_n             (rst_n),
        .tick_4mhz         (tick_4mhz),
        .start_measurement (start_pulse),
        .mic1_pdm          (mic1_pdm),
        .mic2_pdm          (mic2_pdm),
        .angle_out         (angle_out_horizontal),
        .angle_valid       (angle_valid),
        .echo_window       (echo_window_index),
        .echo_found        (echo_found_unused)
    );

    transducer_ping_generator ping_generator (
        .clk               (clk),
        .tick_4mhz         (tick_4mhz),
        .rst_n             (rst_n),
        .start_measurement (start_pulse),
        .drive_a           (transducer_drive_a),
        .drive_b           (transducer_drive_b)
    );

    wire _unused = &{echo_found_unused, 1'b0};

endmodule
