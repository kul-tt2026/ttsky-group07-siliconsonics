`default_nettype none

module min_finder (
    input wire [31:0] n1,
    input wire [31:0] n2,
    input wire [31:0] n3,
    output reg [2:0] min_index,   
    output reg [31:0] min_val     
);

    always @(*) begin
        if (n1 <= n2 && n1 <= n3) begin
            min_val   = n1;
            min_index = 3'b001;
        end else if (n2 <= n1 && n2 <= n3) begin
            min_val   = n2;
            min_index = 3'b010;
        end else begin
            min_val   = n3;
            min_index = 3'b100;
        end
    end

endmodule