`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
that can be driven / tested by the cocotb test.py.
*/
module tb ();
    // Wire up the inputs and outputs:
    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    reg [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    `ifdef GL_TEST
        wire VPWR = 1'b1;
        wire VGND = 1'b0;
    `endif

    wire [11:0] echo_window_index = {uio_out[3:0], uo_out[7:0]};
    wire echo_found = uio_out[4];
    wire transducer_drive_a = uio_out[5];
    wire transducer_drive_b = uio_out[6];
    wire mic_clk = uio_out[7];

    wire start_measurement = ui_in[0];
    wire mic1_pdm = ui_in[1];
    wire restart_mic = ui_in[7];


    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        ena = 1'b1;
        ui_in = 8'b0;
        uio_in = 8'b0;
    end

    // Dump the signals to a FST file. You can view it with gtkwave or surfer.
    initial begin
        $dumpfile("tb.fst");
        $dumpvars(0, tb);
        #1;
    end

    // Replace tt_um_example with your module name:
    tt_um_siliconsonics user_project (
        // Include power ports for the Gate Level test:
        `ifdef GL_TEST
            .VPWR(VPWR),
            .VGND(VGND),
        `endif

            .ui_in(ui_in),    // Dedicated inputs
            .uo_out(uo_out),   // Dedicated outputs
            .uio_in(uio_in),   // IOs: Input path
            .uio_out(uio_out),  // IOs: Output path
            .uio_oe(uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
            .ena(ena),      // enable - goes high when design is selected
            .clk(clk),      // clock
            .rst_n(rst_n)     // not reset
    );

    wire signed [7:0] atan2_x_in;
    wire signed [7:0] atan2_y_in;
    wire atan2_load_input;

    wire atan2_angle_valid;
    wire signed [11:0] atan2_angle_out;

    atan2_cordic cordic_testing (
        `ifdef GL_TEST
            .VPWR(VPWR),
            .VGND(VGND),
        `endif

        .clk(clk),
        .rst_n(rst_n),
        .x_in(atan2_x_in),
        .y_in(atan2_y_in),
        .load_input(atan2_load_input),
        .angle_valid(atan2_angle_valid),
        .angle_out(atan2_angle_out)
    );

endmodule



