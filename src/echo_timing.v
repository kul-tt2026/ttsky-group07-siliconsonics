// WARNING: Requires 40MHz clock so 40MHz / 10 = 4MHz

module clk_div_10 (
    input wire clk,
    input wire rst_n,
    output reg tick_4mhz
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


module ref_sig (
    input wire clk,
    input wire tick_4mhz,
    input wire rst_n,
    input wire restart,
    output reg ref_sin,
    output reg ref_cos
);
    reg [5:0] index; // 0->49 (0 63)

    always @(posedge clk or negedge rst_n) begin
        if ((!rst_n) || restart) begin
            index <= 6'd0;
            ref_cos <= 1'b1;
            ref_sin <= 1'b1;
        end

        else if (tick_4mhz) begin
            // 40kHz cosine is 25 cycles ahead at 4MHz
            if (index == 6'd24) begin
                ref_cos <= ~ref_cos;
            end


            if (index == 6'd49) begin
                index <= 6'd0;
                ref_sin <= ~ref_sin;
            end
            else begin
                index <= index + 1;
            end
        end
    end

endmodule

module correlator (
    input wire clk,
    input wire tick_4mhz,
    input wire rst_n,
    input wire restart,
    input wire new_window, // resets to +1 or -1 based on ref_pdm
    input wire mic_pdm, // microphone input
    input wire ref_pdm, // reference signal (square cos/sin approximation)
    output reg signed [7:0] cumsum // range: -100 to +100 => 7 bits + sign
);
    wire comp = mic_pdm ^ ref_pdm;

    always @(posedge clk or negedge rst_n) begin
        if ((!rst_n) || restart)
            cumsum <= 8'b0;
        else if (tick_4mhz &&new_window) begin
            if (comp)
                cumsum <= -1;
            else
                cumsum <= 1;
        end
        else if (tick_4mhz) begin
            // comp == 1 when NOT equal -> -1, otherwise +1
            if (comp)
                cumsum <= cumsum - 1;
            else
                cumsum <= cumsum + 1;
        end
    end

endmodule

module windowed_iq_demodulator (
    input wire clk,
    input wire tick_4mhz,
    input wire rst_n,
    input wire restart,
    input wire mic_pdm,
    output reg signed [7:0] I,
    output reg signed [7:0] Q,
    output reg iq_valid,
    output reg [11:0] window_counter  // 12-bit -> 4096 windows -> ~0.1s
);
    wire ref_sin;
    wire ref_cos;

    wire signed [7:0] corr_I;
    wire signed [7:0] corr_Q;

    reg [6:0] sample_index; // 0->99 (0 127)
    reg new_window_reg;

    // resets correlators, HI on first sample of each window, LO on subsequent samples
    wire new_window = new_window_reg;

    ref_sig reference_signals (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .restart(restart),
        .ref_cos(ref_cos),
        .ref_sin(ref_sin)
    );

    correlator cos_correlator (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .restart(restart),
        .new_window(new_window),
        .mic_pdm(mic_pdm),
        .ref_pdm(ref_cos),
        .cumsum(corr_I)
    );

    correlator sin_correlator (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .restart(restart),
        .new_window(new_window),
        .mic_pdm(mic_pdm),
        .ref_pdm(ref_sin),
        .cumsum(corr_Q)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || restart) begin
            window_counter <= 12'd0;
            sample_index <= 7'd0;
            new_window_reg <= 1'b0;

            iq_valid <= 1'b0;
            I <= 8'd0;
            Q <= 8'd0;
        end
        else if (tick_4mhz) begin
            iq_valid <= 1'b0;
            new_window_reg <= (sample_index == 7'd99);

            if (sample_index == 7'd99) begin
                I <= corr_I;
                Q <= corr_Q;
                iq_valid <= 1'b1;

                sample_index <= 7'd0;
                window_counter <= window_counter + 1;
            end
            else begin
                sample_index <= sample_index + 1;
            end
        end
    end

endmodule

module first_echo_timing (
    input wire clk,
    input wire tick_4mhz,
    input wire rst_n,
    input wire restart,
    input wire mic_pdm,
    output reg [11:0] echo_window_index,
    output reg echo_found
);
    wire iq_valid;
    wire [11:0] window_counter;

    wire signed [7:0] I;
    wire signed [7:0] Q;

    wire [7:0] abs_I = I[7] ? -I : I;
    wire [7:0] abs_Q = Q[7] ? -Q : Q;
    wire [7:0] sig_strength = abs_I + abs_Q; // abs(I) + abs(Q), I and Q always within [-100, 100] -> 8 bits

    windowed_iq_demodulator mic_windowed_iq_demodulator (
        .clk(clk),
        .tick_4mhz(tick_4mhz),
        .rst_n(rst_n),
        .restart(restart),
        .mic_pdm(mic_pdm),
        .I(I),
        .Q(Q),
        .iq_valid(iq_valid),
        .window_counter(window_counter)
    );

    always @(posedge clk or negedge rst_n) begin
        if ((!rst_n )|| restart) begin
            echo_window_index <= 12'd0;
            echo_found <= 1'b0;
        end
        else if (tick_4mhz && iq_valid && !(echo_found)) begin
            if ((sig_strength >= 8'd16) && (window_counter >= 12'd64)) begin // 16: empirical noise/echo threshold, 64: empirical echo_end threshold
                echo_window_index <= window_counter;
                echo_found <= 1'b1;
            end
        end
    end

endmodule


module main (
    input wire clk,
    input wire rst_n,
    input wire restart,
    input wire mic_pdm,
    output wire [11:0] echo_window_index,
    output wire echo_found
);
    wire tick_4mhz;

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

endmodule