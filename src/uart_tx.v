// Minimal UART transmitter: 8 data bits, no parity, 1 stop bit, LSB first.
//
// Handshake: present a byte on data with valid high. It is accepted on the
// clock where valid && ready are both high. ready is low while a byte is
// being shifted out.
//
// CLKS_PER_BIT = clk / baud. At 40 MHz: 115200 baud -> 347 (0.06% error).
module uart_tx #(
    parameter CLKS_PER_BIT = 347
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       valid,
    output wire       ready,
    output reg        tx
);
    reg        active;
    reg [9:0]  shreg;     // {stop, data[7:0], start}
    reg [3:0]  bit_idx;   // 0..9
    reg [9:0]  baud_cnt;

    assign ready = ~active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active   <= 1'b0;
            shreg    <= 10'h3FF;
            bit_idx  <= 4'd0;
            baud_cnt <= 10'd0;
            tx       <= 1'b1;
        end
        else if (!active) begin
            tx <= 1'b1;
            if (valid) begin
                shreg    <= {1'b1, data, 1'b0};
                bit_idx  <= 4'd0;
                baud_cnt <= 10'd0;
                active   <= 1'b1;
            end
        end
        else begin
            tx <= shreg[0];
            if (baud_cnt == CLKS_PER_BIT - 1) begin
                baud_cnt <= 10'd0;
                shreg    <= {1'b1, shreg[9:1]};
                if (bit_idx == 4'd9)
                    active <= 1'b0;
                else
                    bit_idx <= bit_idx + 1'b1;
            end
            else begin
                baud_cnt <= baud_cnt + 1'b1;
            end
        end
    end
endmodule
