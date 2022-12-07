`default_nettype none

module data_buffer (
    // general inputs
    input var clk,
    input var n_rst,
    input var flush,
    input var clear,
    // general outputs
    output var [6:0] buffer_occ,
    // rx inputs
    input var [1:0] get_rx_data,
    input var store_rx_data,
    input var [7:0] rx_data_in,
    // rx outputs
    output var [31:0] rx_data_out,
    // tx inputs
    input var get_tx_data,
    input var [1:0] store_tx_data,
    input var [31:0] tx_data_in,
    // tx outputs
    output var [7:0] tx_data_out
);

    clocking ce @(posedge clk, negedge n_rst);
    endclocking

    logic [31:0] out;
    alias out = rx_data_out; alias tx_data_out = rx_data_out[7:0];

    logic [7:0] mem[63:0];
    logic [6:0] write_ptr;
    logic [6:0] read_ptr;

    logic sync_clear;
    assign sync_clear = flush || clear;

    assign buffer_occ = write_ptr - read_ptr;

    assign out = {
        mem[read_ptr+3], mem[read_ptr+2], mem[read_ptr+1], mem[read_ptr]
    };

    /* svlint off sequential_block_in_always_ff */
    // updating write_ptr and mem together makes more sense than seperate
    always_ff @(ce)
        if (!n_rst) begin
            write_ptr <= 0;
            mem       <= '{64{0}};
        end else if (sync_clear) begin
            write_ptr <= 0;
            mem       <= '{64{0}};
        end else if (store_rx_data) begin
            write_ptr      <= write_ptr + 1;
            mem[write_ptr] <= rx_data_in;
        end else if (store_tx_data) begin
            write_ptr      <= write_ptr + 1;
            mem[write_ptr] <= tx_data_in[7:0];
            if (store_tx_data == 2) begin
                write_ptr        <= write_ptr + 2;
                mem[write_ptr+1] <= tx_data_in[15:8];
            end else if (store_tx_data > 2) begin
                write_ptr <= write_ptr + 4;
                {mem[write_ptr+3], mem[write_ptr+2]} <= tx_data_in[31:16];
            end
        end else if (buffer_occ == 0) begin
            write_ptr <= 0;
            mem       <= '{64{0}};
        end else mem <= mem;
    /* svlint on sequential_block_in_always_ff */

    always_ff @(ce)
        if (!n_rst) read_ptr <= 0;
        else if (sync_clear) read_ptr <= 0;
        else if (get_tx_data) read_ptr <= read_ptr + 1;
        else if (get_rx_data == 1) read_ptr <= read_ptr + 1;
        else if (get_rx_data == 2) read_ptr <= read_ptr + 2;
        else if (get_rx_data > 2) read_ptr <= read_ptr + 4;
        else if (buffer_occ == 0) read_ptr <= 0;
        else read_ptr <= read_ptr;

endmodule