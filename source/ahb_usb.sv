`default_nettype none

module ahb_usb (
    // general inputs
    input var clk,
    input var n_rst,
    // general outputs
    output var d_mode,
    // ahb inputs
    input var hsel,
    input var [3:0] haddr,
    input var [1:0] htrans,
    input var [2:0] hburst,
    input var [1:0] hsize,
    input var hwrite,
    input var [31:0] hwdata,
    // ahb outputs
    output var [31:0] hrdata,
    output var hresp,
    output var hready,
    // rx inputs
    input var rx_dp,
    input var rx_dm,
    // tx outputs
    output var tx_dp,
    output var tx_dm
);
    // out of rx
    logic [2:0] rx_packet;
    logic [7:0] rx_packet_data;
    logic
        rx_data_ready,
        rx_transfer_active,
        rx_error,
        flush,
        store_rx_packet_data;
    // out of tx
    logic tx_transfer_active, tx_error, get_tx_packet_data;
    // out of data buffer
    logic [31:0] rx_data;
    logic [7:0] tx_packet_data;
    logic [6:0] buffer_occupancy;
    // out of slave
    logic tx_start;
    logic [1:0] get_rx_data, store_tx_data, tx_packet;
    logic [31:0] tx_data;
    logic clear;

    ahb_slave controller (.*);
    data_buffer buffer (.*);

    usb_rx rx (
        .*,
        .dp(rx_dp),
        .dm(rx_dm)
    );

    usb_tx tx (
        .*,
        .dp(tx_dp),
        .dm(tx_dm)
    );

endmodule
