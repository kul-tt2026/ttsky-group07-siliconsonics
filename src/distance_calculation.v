module distance_calculator (
    input wire clk,
    input wire rst_n,
    input wire [15:0] expected_window, // Wide enough for 4 million cycles (4 MHz * 1 sec)
    input wire valid_in,
    
    output reg [8:0] distance_out,    // Calculated distance in cm
    output reg valid_out
);
    reg [32:0] distance;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            distance_out <= '0;
            valid_out    <= 1'b0;
        end 
        else begin
            valid_out <= valid_in;
            if (valid_in) begin
                // Formula: 
                // ((expected_window + 99)/ 4_000_000) * 343 / 2 (in meters)
                // = ((expected_window + 99)/ 40_000) * 343 / 2 (in cm)
                // = ((expected_window + 99)/ 65_536) * 562 / 2 
                // = ((expected_window + 99)/ (2^16)) * 281
                // = ((expected_window + 99) * 281) >> 16
                // This replaces the expensive division by 4,000,000 and /2 with a fast multiplication and shift.
                distance = (((expected_window + 16'd99) * 9'd281) >> 16);
                distance_out <= distance[8:0];
                $display("Expected_window: %0d | distance_out: %0d cm", expected_window, distance);
            end
        end
    end

endmodule