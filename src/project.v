`default_nettype none

// Pinout
//
//   ui_in[0]   start_measurement   rising edge = one ping (if allowed)
//   ui_in[1]   mic1_pdm
//   ui_in[2]   mic2_pdm
//   ui_in[3]   mux_sel             0: window index on data_out, 1: angle + status
//   ui_in[4]   uart_rx             115200 8N1
//   ui_in[5]   auto_enable         level; auto-measure every second while high
//   ui_in[6]   single_mic          1: only mic1 is fitted, bearing reads 0
//   ui_in[7]   restart_mic
//
//   uo_out[7:0]  data_out[7:0]
//   uio_out[3:0] data_out[11:8]
//   uio_out[4]   uart_tx
//   uio_out[5]   transducer_drive_a
//   uio_out[6]   transducer_drive_b
//   uio_out[7]   mic_clk
//
// data_out with mux_sel = 0:  echo_window_index[11:0]
// data_out with mux_sel = 1:  [5:0]  angle
//                             [6]    single_mic
//                             [7]    0
//                             [8]    result_ready  (sticky until next ping)
//                             [9]    busy          (measurement in progress)
//                             [10]   mic_ready
//                             [11]   auto_mode
module tt_um_siliconsonics (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire start_measurement = ui_in[0];
    wire mic1_pdm          = ui_in[1];
    wire mic2_pdm          = ui_in[2];
    wire mux_sel           = ui_in[3];
    wire uart_rx           = ui_in[4];
    wire auto_enable       = ui_in[5];
    wire single_mic        = ui_in[6];
    wire restart_mic       = ui_in[7];

    wire [11:0] echo_window_index;
    wire [5:0]  angle_out_horizontal;
    wire        transducer_drive_a;
    wire        transducer_drive_b;
    wire        mic_clk;
    wire        uart_tx;
    wire        mic_ready;
    wire        auto_mode;
    wire        busy;
    wire        result_ready;
    wire [11:0] mux_data_out;

    main main_inst (
        .clk                  (clk),
        .rst_n                (rst_n),
        .start_measurement    (start_measurement),
        .auto_enable          (auto_enable),
        .mic1_pdm             (mic1_pdm),
        .mic2_pdm             (mic2_pdm),
        .single_mic           (single_mic),
        .restart_mic          (restart_mic),
        .uart_rx              (uart_rx),
        .echo_window_index    (echo_window_index),
        .angle_out_horizontal (angle_out_horizontal),
        .transducer_drive_a   (transducer_drive_a),
        .transducer_drive_b   (transducer_drive_b),
        .mic_clk              (mic_clk),
        .uart_tx              (uart_tx),
        .mic_ready            (mic_ready),
        .auto_mode            (auto_mode),
        .busy                 (busy),
        .result_ready         (result_ready)
    );

    // Angle mode fills the otherwise-dead upper bits with status flags.
    wire [11:0] angle_and_status = {auto_mode, mic_ready, busy, result_ready,
                                    1'b0, single_mic, angle_out_horizontal};

    data_mux #(
        .WIDTH(12)
    ) data_mux_inst (
        .sel      (mux_sel),
        .data0    (echo_window_index),
        .data1    (angle_and_status),
        .data_out (mux_data_out)
    );

    assign uo_out[7:0]  = mux_data_out[7:0];
    assign uio_out[3:0] = mux_data_out[11:8];
    assign uio_out[4]   = uart_tx;
    assign uio_out[5]   = transducer_drive_a;
    assign uio_out[6]   = transducer_drive_b;
    assign uio_out[7]   = mic_clk;

    assign uio_oe[7:0]  = 8'b11111111;

    wire _unused = &{ena, uio_in, 1'b0};

endmodule

`default_nettype wire
