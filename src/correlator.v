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
    wire comp = mic_pdm ^ ref_pdm;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cumsum <= 8'b0;
        end
        else begin
            if (start_measurement) begin
                cumsum <= 8'b0;
            end
            else if (tick_4mhz && new_window) begin
                cumsum <= comp ? (-8'sd1) : (8'sd1);
            end
            else if (tick_4mhz) begin
                // comp == 1 when NOT equal -> -1, otherwise +1
                cumsum <= comp ? (cumsum - 8'sd1) : (cumsum + 8'sd1);
            end
        end
    end

endmodule
