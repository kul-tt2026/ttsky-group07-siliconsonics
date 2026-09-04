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
