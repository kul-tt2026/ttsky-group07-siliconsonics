// 8-entry byte FIFO. Buffers outgoing UART bytes so the message writer can
// push most of a frame in a few clocks and the transmitter drains it at baud
// rate. The writer stalls on full, so depth only affects how long it holds a
// message, never its content.
//
// rd_data always shows the oldest byte (combinational); assert rd_en for
// one clock to pop it. Writes when full and reads when empty are ignored.
module byte_fifo (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       wr_en,
    input  wire [7:0] wr_data,
    input  wire       rd_en,
    output wire [7:0] rd_data,
    output wire       full,
    output wire       empty
);
    reg [7:0] mem [0:7];
    reg [2:0] wr_ptr;
    reg [2:0] rd_ptr;
    reg [3:0] count;

    assign full    = (count == 4'd8);
    assign empty   = (count == 4'd0);
    assign rd_data = mem[rd_ptr];

    wire do_wr = wr_en & ~full;
    wire do_rd = rd_en & ~empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 3'd0;
            rd_ptr <= 3'd0;
            count  <= 4'd0;
        end
        else begin
            if (do_wr) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (do_rd)
                rd_ptr <= rd_ptr + 1'b1;

            case ({do_wr, do_rd})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule
