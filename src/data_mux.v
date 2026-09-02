module data_mux #(
    parameter WIDTH = 12
)(
    input wire [WIDTH-1:0] data0,
    input wire [WIDTH-1:0] data1,
    input wire sel,
    output wire [WIDTH-1:0] data_out
);
    assign data_out = sel ? data1 : data0;
endmodule
