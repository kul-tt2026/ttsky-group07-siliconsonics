/*
* Copyright (c) 2024 Your Name
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_siliconsonics (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // All output pins must be assigned. If not used, assign to 0.
    // --- Input mapping -------------------------------------------------------
    wire start_measurement = ui_in[0];
    wire mic_pdm = ui_in[1];

    // --- Internal signals from main ------------------------------------------
    wire [14:0] echo_window_index;
    wire echo_found;

    wire transducer_drive_a;
    wire transducer_drive_b;

    wire restart_mic = ui_in[7];
    wire mic_clk;

    // --- Core design ---------------------------------------------------------
    main main_inst (
        .clk(clk),
        .rst_n(rst_n),
        .restart_mic(restart_mic),
        .start_measurement(start_measurement),
        .mic_pdm(mic_pdm),
        .echo_window_index(echo_window_index),
        .echo_found(echo_found),
        .transducer_drive_a(transducer_drive_a),
        .transducer_drive_b(transducer_drive_b),
        .mic_clk(mic_clk)
    );

    // --- Output mapping ------------------------------------------------------
    // Dedicated outputs: lower 8 bits of window index
    assign uo_out[7:0]  = echo_window_index[7:0];

    // Bidirectional outputs: upper 4 bits of window index + echo_found
    assign uio_out[6:0] = echo_window_index[14:8];
    assign uio_out[7] = echo_found;

    // Enable bidirectional pins as outputs where we drive data
    assign uio_oe[4:0] = 5'b11111;  // index[11:8] + echo_found
    assign uio_oe[7:5] = 3'b00000;  // unused pins as inputs

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, uio_in, ui_in[6:2], 1'b0};

endmodule
