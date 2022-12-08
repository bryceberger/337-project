module crc #(
    nbits,
    parameter logic [(nbits-1):0] polynomial,
    parameter logic [(nbits-1):0] residual
)(
    input wire clk, input wire n_rst,
    input wire data,
    input wire shift,
    input wire clear,
    output reg [(nbits-1):0] crc,
    output wire valid
);

    logic [(nbits-1):0] int_crc;
    assign crc = ~int_crc;

    logic flip;
    assign flip = data ^ int_crc[nbits-1];

    logic [(nbits-1):0] s_int_crc;
    always_comb begin
        s_int_crc[0] = polynomial[0] ? flip : data;
        for (int i = 1; i < nbits; i++)
            s_int_crc[i] = int_crc[i-1] ^ (polynomial[i] ? flip : 1'b0);
    end

    logic [(nbits-1):0] n_int_crc;
    assign n_int_crc = clear ? ~0 : (shift ? s_int_crc : int_crc);
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) int_crc <= ~0;
        else int_crc <= n_int_crc;

    assign valid = int_crc == residual;

endmodule
