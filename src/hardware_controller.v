// WARNING, sends one impulse on startup

module transducer_ping_generator (
    input wire clk,
    input wire tick_4mhz,
    input wire rst_n,
    input wire start_measurement,
    output reg drive_a,
    output reg drive_b
);

    // 40kHz ping, 1 period: 1000ticks@40MHz -> 100ticks@4MHz 

    reg [5:0] counter; // 0->49 (0 64)

    reg [4:0] half_period_counter; // 0->15 (0 31) 2x8=16 half periods
    wire running = !(half_period_counter == 5'd16);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 6'd0;
            drive_a <= 1'b0;
            drive_b <= 1'b0;
            half_period_counter <= 5'd16; // 16 == turned off
        end
        else begin
            if (start_measurement) begin
                counter <= 6'd0;
                drive_a <= 1'b0;
                drive_b <= 1'b0;
                half_period_counter <= 5'd0;
            end
            else if (tick_4mhz && running) begin
                if (counter == 6'd48) begin
                    counter <= counter + 1;

                    drive_a <= 1'b0;
                    drive_b <= 1'b0;
                end
                else if (counter == 6'd49) begin
                    counter <= 6'd0;
                    drive_a <= 1'b0;
                    drive_b <= 1'b0;
                    half_period_counter <= half_period_counter + 1;
                end
                else begin
                    counter <= counter + 1;

                    drive_a <= half_period_counter[0];
                    drive_b <= ~half_period_counter[0];
                end
            end
        end
    end

endmodule


module ultrasonic_mic_powerup_sequence (
    input wire clk,
    input wire tick_4mhz,
    input wire rst_n,
    input wire restart,
    output reg mic_clk,
    output wire mic_ready
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
            if (us_mode == 1'b0 && cycle_count == 4'd9) begin // 2MHz -> half period = 10 cycles
                cycle_count <= 4'd0;
                mic_clk <= ~mic_clk;
            end
            else if (us_mode == 1'b1 && cycle_count == 4'd4) begin // 4MHz -> half period = 5 cycles
                cycle_count <= 4'd0;
                mic_clk <= ~mic_clk;
            end
            else begin
                cycle_count <= cycle_count + 1'b1;
            end
        end
    end
endmodule