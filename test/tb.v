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

    // Edge counter for the mic clock, so cocotb can read a frequency once
    // per ms instead of waking Python on every 40 MHz clock edge.
    reg [31:0] mic_clk_edges = 32'd0;
    always @(posedge mic_clk) mic_clk_edges <= mic_clk_edges + 1;

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

    `ifndef GL_TEST
        // DEBUG
        always @(posedge clk) if (user_project.main_inst.controller.ext_rise)
            $display("DBG %0t ext_rise: can=%b lockout_ok=%b mic_ready=%b since=%0d req=%b do=%b auto_fire=%b cmd=%b",
                $time, user_project.main_inst.controller.can_ping, user_project.main_inst.controller.lockout_ok,
                user_project.main_inst.controller.mic_ready, user_project.main_inst.controller.since_ping,
                user_project.main_inst.controller.ping_req, user_project.main_inst.controller.do_ping,
                user_project.main_inst.controller.auto_fire, user_project.main_inst.controller.cmd_ping);
        always @(posedge clk) if (user_project.main_inst.controller.start_pulse) $display("DBG %0t START_PULSE", $time);

        // Shorten the controller timers for RTL simulation. The real
        // values (1 s / 400 ms / 102.4 ms) would make every test take
        // minutes. Icarus -P cannot reach nested instances, so defparam.
        // tick_4mhz units: 4000 = 1 ms.
        defparam user_project.main_inst.AUTO_PERIOD_TICKS = 22'd120000;  // 30 ms
        defparam user_project.main_inst.LOCKOUT_TICKS     = 22'd80000;   // 20 ms
        defparam user_project.main_inst.MEAS_TICKS        = 22'd60000;   // 15 ms

        // ------------------------------------------------------------------
        // Anything cocotb WRITES to must be a reg. A wire with no Verilog
        // driver stays at X no matter what the Python assigns to it.
        // ------------------------------------------------------------------

        reg signed [15:0] atan2_x_in_16;
        reg signed [15:0] atan2_y_in_16;
        reg               atan2_load_input_16;

        wire              atan2_angle_valid_16;
        wire       [11:0] atan2_angle_out_16;

        initial begin
            atan2_x_in_16       = 16'sd0;
            atan2_y_in_16       = 16'sd0;
            atan2_load_input_16 = 1'b0;
        end

        atan2_cordic_16b cordic_testing_16 (
            .clk(clk),
            .rst_n(rst_n),
            .x_in(atan2_x_in_16),
            .y_in(atan2_y_in_16),
            .load_input(atan2_load_input_16),
            .angle_valid(atan2_angle_valid_16),
            .angle_out(atan2_angle_out_16)
        );

        reg        start_measurement_ead;
        reg        mic1_pdm_t;
        reg        mic2_pdm_t;

        wire       tick_4mhz;
        wire [5:0] angle_out_ead;
        wire       angle_valid_ead;
        wire [11:0] echo_window_ead;
        wire       echo_found_ead;

        initial begin
            start_measurement_ead = 1'b0;
            mic1_pdm_t            = 1'b0;
            mic2_pdm_t            = 1'b0;
        end

        clk_div_10 clock_4mhz_module (
            .clk(clk),
            .rst_n(rst_n),
            .tick_4mhz(tick_4mhz)
        );

        echo_angle_detector echo_angle_detector_test (
            .clk(clk),
            .rst_n(rst_n),
            .tick_4mhz(tick_4mhz),
            .start_measurement(start_measurement_ead),
            .mic1_pdm(mic1_pdm_t),
            .mic2_pdm(mic2_pdm_t),
            .angle_out(angle_out_ead),
            .angle_valid(angle_valid_ead),
            .echo_window(echo_window_ead),
            .echo_found(echo_found_ead)
        );

    `endif

endmodule
