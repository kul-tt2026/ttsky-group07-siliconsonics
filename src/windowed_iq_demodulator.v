module windowed_iq_demodulator (
    input wire clk, // 40MHz clock
    input wire tick_4mhz, // 4MHz 10% duty cycle
    input wire rst_n,
    input wire start_measurement, // start measuring I/Q and updating the window starting at 0
    input wire mic_pdm, // mic pdm signal @ 4MHz

    output reg signed [7:0] I, // in-phase component of mic_pdm
    output reg signed [7:0] Q, // quadrature component of mic_pdm
    output reg iq_valid, // when HI, I/Q values are valid (true every 100 ticks @ 4MHz)
    output reg [11:0] window_counter  // 12-bit -> 4096 windows -> ~0.1s
);
    wire ref_sin;
    wire ref_cos;

    wire signed [7:0] corr_I;
    wire signed [7:0] corr_Q;

    reg [6:0] sample_index; // 0->100 (0 127)
    reg new_window_reg; // for storing whether a new window should be started

    // resets correlators, HI on first sample of each window, LO on subsequent samples
    wire new_window = new_window_reg;

    wire active = (window_counter != 12'hFFF); // active while last window is not reached

    ref_sig reference_signals (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .restart(start_measurement),
        .ref_cos(ref_cos),
        .ref_sin(ref_sin)
    );

    correlator cos_correlator (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .start_measurement(start_measurement),
        .new_window(new_window),
        .mic_pdm(mic_pdm),
        .ref_pdm(ref_cos),
        .cumsum(corr_I)
    );

    correlator sin_correlator (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .start_measurement(start_measurement),
        .new_window(new_window),
        .mic_pdm(mic_pdm),
        .ref_pdm(ref_sin),
        .cumsum(corr_Q)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_counter <= 12'hFFF;

            sample_index <= 7'd0;
            new_window_reg <= 1'b0;
            iq_valid <= 1'b0;
            I <= 8'd0;
            Q <= 8'd0;
        end
        else begin
            if (start_measurement) begin
                window_counter <= 12'd0;
                sample_index <= 7'd0;
                new_window_reg <= 1'b0;

                iq_valid <= 1'b0;
                I <= 8'd0;
                Q <= 8'd0;
            end
            else if (tick_4mhz && active) begin
                iq_valid <= 1'b0;
                new_window_reg <= (sample_index == 7'd99); // queue new window on tick "100"=0

                if (sample_index == 7'd100) begin
                    I <= corr_I;
                    Q <= corr_Q;
                    window_counter <= window_counter + 1;
                    iq_valid <= 1'b1;
                    sample_index <= 7'd1;
                end
                else begin
                    sample_index <= sample_index + 1;
                end
            end
        end
    end

endmodule
