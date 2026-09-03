module tt_um_siliconsonics (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena,
    input wire clk,
    input wire rst_n
);

    wire start_measurement = ui_in[0];
    wire mic1_pdm = ui_in[1];
    wire mic2_pdm = ui_in[2];
    wire mux_sel = ui_in[3];
    wire restart_mic = ui_in[7];

    wire [11:0] echo_window_index;
    wire [5:0]  angle_out_horizontal;
    wire angle_valid_horizontal;
    wire [11:0] mux_data_out;

    wire transducer_drive_a;
    wire transducer_drive_b;
    wire mic_clk;

    main main_inst (
        .clk(clk),
        .rst_n(rst_n),
        .restart_mic(restart_mic),
        .start_measurement(start_measurement),
        .mic1_pdm(mic1_pdm),
        .mic2_pdm(mic2_pdm),
        .echo_window_index(echo_window_index),
        .transducer_drive_a(transducer_drive_a),
        .transducer_drive_b(transducer_drive_b),
        .mic_clk(mic_clk),
        .angle_out_horizontal(angle_out_horizontal),
        .angle_valid_horizontal(angle_valid_horizontal)
    );

    data_mux #(
        .WIDTH(12)
    ) data_mux_inst (
        .data0(echo_window_index),
        .data1({6'b0, angle_out_horizontal}),
        .sel(mux_sel),
        .data_out(mux_data_out)
    );

    assign uo_out[7:0] = mux_data_out[7:0];

    assign uio_out[3:0] = mux_data_out[11:8];
    assign uio_out[4] = angle_valid_horizontal;
    assign uio_out[5] = transducer_drive_a;
    assign uio_out[6] = transducer_drive_b;
    assign uio_out[7] = mic_clk;

    assign uio_oe[7:0] = 8'b11111111;

    wire _unused = &{ena, uio_in, ui_in[6:4], 1'b0};

endmodule