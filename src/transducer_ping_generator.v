// Drives drive_a/drive_b as a 40kHz ping of cfg_halfcycles half periods.
// deadtime: 2 cycles @ 4MHz == 500ns
module transducer_ping_generator (
    input wire clk,
    input wire tick_4mhz,
    input wire rst_n,
    input wire start_measurement,
    input wire [4:0] cfg_halfcycles, // 16 = the default 8-period burst
    output reg drive_a,
    output reg drive_b
);

    // 40kHz ping, 1 period: 1000ticks@40MHz -> 100ticks@4MHz 

    reg [5:0] counter; // 0->49 (0 64)

    reg [4:0] half_period_counter;
    reg running;   // only start_measurement starts a burst

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 6'd0;
            drive_a <= 1'b0;
            drive_b <= 1'b0;
            half_period_counter <= 5'd0;
            running <= 1'b0;
        end
        else begin
            if (start_measurement) begin
                counter <= 6'd0;
                drive_a <= 1'b0;
                drive_b <= 1'b0;
                half_period_counter <= 5'd0;
                running <= (cfg_halfcycles != 5'd0);
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
                    half_period_counter <= half_period_counter + 1'b1;
                    if (half_period_counter + 1'b1 >= cfg_halfcycles)
                        running <= 1'b0;
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
