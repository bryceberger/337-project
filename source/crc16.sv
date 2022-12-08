module crc16 (
    input wire clk, input wire n_rst,
    input wire data,
    input wire shift,
    input wire clear,
    output reg [15:0] crc,
    output wire valid
);
    crc #(
        .nbits(16),
        .polynomial(16'b1000000000000101),
        .residual(16'b1000000000001101)
    ) CRC (.*);
endmodule
