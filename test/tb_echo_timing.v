module tb;
    reg clk;
    reg rst_n;
    reg restart;
    reg mic_pdm;
    wire [11:0] echo_window_index;
    wire echo_found;

    initial begin
        clk = 0;
        forever #12.5 clk = ~clk; // 40 MHz clock
    end

    main dut (
        .clk(clk),
        .rst_n(rst_n),
        .restart(restart),
        .mic_pdm(mic_pdm),
        .echo_window_index(echo_window_index),
        .echo_found(echo_found)
    );

endmodule