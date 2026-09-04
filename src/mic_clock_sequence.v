// Set's the mic_clk to follow the powerup sequence:
// Powered off -> Normal mode -> Ultrasonic mode -> ready.
// When the microphone should be ready mic_ready is set to HI
module ultrasonic_mic_powerup_sequence (
    input wire clk,
    input wire tick_4mhz,
    input wire rst_n,
    input wire restart,
    output reg mic_clk, // clock for pdm mic
    output wire mic_ready // turns HI when sequence is finished
);
    reg us_mode;

    reg [3:0] cycle_count;
    reg [18:0] mode_counter; // 0->220000->440000 (0 524288), 50ms@4MHz + margin, OFF->normal mode -> ultrasonic mode

    assign mic_ready = (mode_counter == 19'd440000);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_counter <= 19'd0;
            us_mode <= 1'b0;
        end
        else if (restart) begin
            mode_counter <= 19'd0;
            us_mode <= 1'b0;
        end
        else if (tick_4mhz) begin
            if (mode_counter < 440000) begin
                mode_counter <= mode_counter + 1'b1;
                if (mode_counter == 220000 )
                    us_mode <= 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 4'd0;
            mic_clk <= 1'b0;
        end
        else if (restart) begin
            cycle_count <= 4'd0;
            mic_clk <= 1'b0;
        end
        else begin
            // 2 MHz: half period = 10 cycles, 4 MHz: 5 cycles. ">=" so the
            // switch to ultrasonic mode cannot stretch the half period in
            // progress past its new length.
            if (cycle_count >= (us_mode ? 4'd4 : 4'd9)) begin
                cycle_count <= 4'd0;
                mic_clk <= ~mic_clk;
            end
            else begin
                cycle_count <= cycle_count + 1'b1;
            end
        end
    end
endmodule
