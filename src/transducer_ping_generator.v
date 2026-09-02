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
