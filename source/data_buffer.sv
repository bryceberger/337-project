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
    input var store_rx_packet_data,
    input var [7:0] rx_packet_data,
    // rx outputs
    output var [31:0] rx_data,
    // tx inputs
    input var get_tx_packet_data,
    input var [1:0] store_tx_data,
    input var [31:0] tx_data,
    // tx outputs
    output var [7:0] tx_packet_data
);

    assign tx_packet_data = rx_data[7:0];

    logic [7:0] mem[67:0];
    logic [6:0] write_ptr;
    logic [6:0] read_ptr;

    logic sync_clear;
    assign sync_clear = flush || clear;

    assign buffer_occ = write_ptr - read_ptr;

    assign rx_data = {
        mem[read_ptr+3], mem[read_ptr+2], mem[read_ptr+1], mem[read_ptr]
    };

    /* svlint off sequential_block_in_always_ff */
    /* svlint off explicit_if_else */
    // updating write_ptr and mem together makes more sense than seperate
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) begin
            write_ptr <= 0;
            mem       <= '{68{0}};
        end else if (sync_clear) begin
            write_ptr <= 0;
            mem       <= '{68{0}};
        end else if (store_rx_packet_data) begin
            write_ptr      <= write_ptr + 1;
            mem[write_ptr] <= rx_packet_data;
        end else if (store_tx_data) begin
            write_ptr      <= write_ptr + 1;
            mem[write_ptr] <= tx_data[7:0];
            if (store_tx_data > 1) begin
                write_ptr        <= write_ptr + 2;
                mem[write_ptr+1] <= tx_data[15:8];
            end
            if (store_tx_data > 2) begin
                write_ptr                            <= write_ptr + 4;
                {mem[write_ptr+3], mem[write_ptr+2]} <= tx_data[31:16];
            end
        end else if (buffer_occ == 0) begin
            write_ptr <= 0;
            mem       <= '{68{0}};
        end else mem <= mem;
    /* svlint on explicit_if_else */
    /* svlint on sequential_block_in_always_ff */

    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) read_ptr <= 0;
        else if (sync_clear) read_ptr <= 0;
        else if (get_tx_packet_data) read_ptr <= read_ptr + 1;
        else if (get_rx_data == 1) read_ptr <= read_ptr + 1;
        else if (get_rx_data == 2) read_ptr <= read_ptr + 2;
        else if (get_rx_data > 2) read_ptr <= read_ptr + 4;
        else if (buffer_occ == 0) read_ptr <= 0;
        else read_ptr <= read_ptr;

endmodule
