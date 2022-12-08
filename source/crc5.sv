module crc5 (
    input wire clk, input wire n_rst,
    input wire data,
    input wire shift,
    input wire clear,
    output reg [4:0] crc,
    output wire valid
);
    crc #(
        .nbits(5), .polynomial(5'b00101), .residual(5'b01100)
    ) CRC (.*);
endmodule
