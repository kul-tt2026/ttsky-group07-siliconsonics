// Minimal UART receiver: 8 data bits, no parity, 1 stop bit, LSB first.
//
// Samples each bit at its centre. valid pulses high for one clock when a
// byte has been received with a good stop bit; data holds that byte until
// the next one arrives.
//
// CLKS_PER_BIT = clk / baud. At 40 MHz: 115200 baud -> 347.
module uart_rx #(
    parameter CLKS_PER_BIT = 347
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    // Two-flop synchroniser: rx is asynchronous to clk.
    reg rx_s1, rx_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s1 <= 1'b1;
            rx_s2 <= 1'b1;
        end
        else begin
            rx_s1 <= rx;
            rx_s2 <= rx_s1;
        end
    end

    reg [1:0] state;
    reg [9:0] baud_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shreg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            baud_cnt <= 10'd0;
            bit_idx  <= 3'd0;
            shreg    <= 8'd0;
            data     <= 8'd0;
            valid    <= 1'b0;
        end
        else begin
            valid <= 1'b0;

            case (state)
                IDLE: begin
                    baud_cnt <= 10'd0;
                    bit_idx  <= 3'd0;
                    if (!rx_s2)               // start bit edge
                        state <= START;
                end

                START: begin
                    // Wait to the middle of the start bit and confirm it
                    // is still low; otherwise it was a glitch.
                    if (baud_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        baud_cnt <= 10'd0;
                        state    <= rx_s2 ? IDLE : DATA;
                    end
                    else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 10'd0;
                        shreg    <= {rx_s2, shreg[7:1]};   // LSB first
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end
                    else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 10'd0;
                        state    <= IDLE;
                        if (rx_s2) begin       // good stop bit
                            data  <= shreg;
                            valid <= 1'b1;
                        end
                    end
                    else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
