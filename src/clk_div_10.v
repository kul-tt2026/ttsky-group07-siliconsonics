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
