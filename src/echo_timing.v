// WARNING: Requires 40MHz clock so 40MHz / 10 = 4MHz


// divides clk signal by 10 @ 10% duty cycle
module clk_div_10 (
    input wire clk, // input 40MHz
    input wire rst_n,

    output reg tick_4mhz // output 4MHz
);
    reg [3:0] counter; // 0->9 (0 15)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 4'b0;
            tick_4mhz <= 1'b0;
        end
        else begin
            tick_4mhz <= (counter == 4'd9);
            counter <= (counter == 4'd9) ? 4'd0 : counter + 1;
        end
    end

endmodule


// generates 2 square reference signals with a phase difference of 90 degrees @40kHz
// Square-wave approximation of sin/cos for correlation
module ref_sig (
    input wire clk, // 40MHz clock
    input wire tick_4mhz, // 4MHz 10% duty cycle
    input wire rst_n,
    input wire restart, // restart reference signals

    output reg ref_sin, // sin @ 40kHz
    output reg ref_cos // sin delayed by 25 cycles = cos @ 40kHz
);
    reg [5:0] index; // 0->49 (0 63), 50 ticks @ 4MHz == 1 half period @ 40kHz

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index <= 6'd0;
            ref_cos <= 1'b1;
            ref_sin <= 1'b1;
        end
        else begin
            if (restart) begin
                index <= 6'd0;
                ref_cos <= 1'b1;
                ref_sin <= 1'b1;
            end
            // square wave alternating 0 and 1 for a 40kHz square wave, shifted by 90 deg == 25 cycles
            else if (tick_4mhz) begin
                // 40kHz cosine is 25 cycles ahead at 4MHz
                if (index == 6'd24)
                    ref_cos <= ~ref_cos;
                if (index == 6'd49) begin
                    index <= 6'd0;
                    ref_sin <= ~ref_sin;
                end
                else begin
                    index <= index + 1;
                end
            end
        end
    end

endmodule


//Signed accumulate-and-dump correlator (+1/-1 per sample) for 2 pdm signals @ 4MHz
// when using sin/cos ref_signals results in I/Q components
module correlator (
    input wire clk,
    input wire tick_4mhz, // 4MHz 10% duty cycle
    input wire rst_n,
    input wire start_measurement,
    input wire new_window, // resets to +1 or -1 based on ref_pdm
    input wire mic_pdm, // microphone input
    input wire ref_pdm, // reference signal (square cos/sin approximation)

    output reg signed [7:0] cumsum // range: -100 to +100 => 7 bits + sign
);
    // 100-bit shift register storing past comparison results
    reg [99:0] shift_reg;
    // 100-bit shift register tracking the validity of the historical comparison results
    reg [99:0] shift_reg_valid;

    wire comp = mic_pdm ^ ref_pdm;
    wire signed [7:0] old_comp = shift_reg[99] ? 8'sd1 : -8'sd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cumsum <= 8'b0;
            shift_reg <= 100'b0;
            shift_reg_valid <= 100'b0;
        end
        else begin
            if (start_measurement) begin
                cumsum <= 8'b0;
            end
            else if (tick_4mhz) begin
                // comp == 1 when NOT equal -> -1, otherwise +1
                shift_reg <= {shift_reg[98:0], comp};
                shift_reg_valid <= {shift_reg_valid[98:0], 1'b1};

                // Update running sum: add new sample contribution and subtract the oldest sample shifted out of the window
                cumsum <= (comp ? (cumsum - 8'sd1) : (cumsum + 8'sd1)) + old_comp*shift_reg_valid[99];
            end
        end
    end

endmodule

// calculates I and Q at 40kHz for the mic_pdm signal over 100-sample windows, samples are read @ 4MHz. 
module windowed_iq_demodulator (
    input wire clk, // 40MHz clock
    input wire tick_4mhz, // 4MHz 10% duty cycle
    input wire rst_n,
    input wire start_measurement, // start measuring I/Q and updating the window starting at 0
    input wire mic_pdm, // mic pdm signal @ 4MHz

    output reg signed [7:0] I, // in-phase component of mic_pdm
    output reg signed [7:0] Q, // quadrature component of mic_pdm
    output reg iq_valid, // when HI, I/Q values are valid (true every 100 ticks @ 4MHz)
    output reg [14:0] window_counter  // 12-bit -> 4096 windows -> ~0.1s
);
    wire ref_sin;
    wire ref_cos;

    wire signed [7:0] corr_I;
    wire signed [7:0] corr_Q;

    reg [6:0] sample_index; // 0->99 (0 127)
    reg new_window_reg; // for storing whether a new window should be started

    // resets correlators, HI on first sample of each window, LO on subsequent samples
    wire new_window = new_window_reg;

    wire active = (window_counter != '1); // active while last window is not reached

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
            window_counter <= '1;

            sample_index <= '0;
            new_window_reg <= 1'b0;
            iq_valid <= 1'b0;
            I <= '0;
            Q <= '0;
        end
        else begin
            if (start_measurement) begin
                window_counter <= '0;
                sample_index <= '0;
                new_window_reg <= 1'b0;

                iq_valid <= 1'b0;
                I <= '0;
                Q <= '0;
            end
            else if (tick_4mhz && active) begin
                iq_valid <= 1'b0;
                new_window_reg <= (sample_index == 7'd99);

                if (sample_index >= 7'd99) begin
                    I <= corr_I;
                    Q <= corr_Q;
                    iq_valid <= 1'b1;
                    window_counter <= window_counter + 1;
                end
                else begin
                    sample_index <= sample_index + 1;
                end
            end
        end
    end

endmodule


// Detects first echo by thresholding |I|+|Q| from the I/Q demodulator
// when |I| + |Q| >= threshold: echo_found turns HI and echo_window_index can be read
module first_echo_timing (
    input wire clk,
    input wire tick_4mhz, // 4MHz 10% duty cycle
    input wire rst_n,
    input wire start_measurement, // start
    input wire mic_pdm, // mic pdm signal @ 4MHz

    output reg [14:0] echo_window_index, // window index where |I| + |Q| went over a set threshold
    output reg echo_found // when |I| + |Q| go over the threshold this is set to HI, meaning echo_window_index can be read
);
    wire iq_valid;
    wire [14:0] window_counter;

    wire signed [7:0] I;
    wire signed [7:0] Q;

    wire [7:0] abs_I = I[7] ? -I : I;
    wire [7:0] abs_Q = Q[7] ? -Q : Q;
    wire [7:0] sig_strength = abs_I + abs_Q; // abs(I) + abs(Q), I and Q always within [-100, 100] -> 8 bits

    windowed_iq_demodulator mic_windowed_iq_demodulator (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .start_measurement(start_measurement),
        .mic_pdm(mic_pdm),
        .I(I),
        .Q(Q),
        .iq_valid(iq_valid),
        .window_counter(window_counter)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            echo_window_index <= 15'd0;
            echo_found <= 1'b0;
        end
        else begin
            if (start_measurement) begin
                echo_window_index <= '0;
                echo_found <= 1'b0;
            end
            else if (tick_4mhz && iq_valid && !echo_found) begin
                if (sig_strength >= 8'd60 && window_counter >= 15'd6301) begin // 16: empirical noise/echo threshold, 64: empirical echo_end threshold
                    echo_window_index <= window_counter-1;
                    echo_found <= 1'b1;
                end
            end
        end
    end

endmodule