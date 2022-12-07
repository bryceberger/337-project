module usb_rx (
    input wire clk, input wire n_rst,
    // USB input lines
    input wire dp, input wire dm,
    // Outputs to AHB-lite interface
    output wire [2:0] rx_packet,
    output wire rx_data_ready,
    output wire rx_transfer_active,
    output wire rx_error,
    // I/O from FIFO
    output wire flush, output wire store_rx_packet_data,
    output wire [7:0] rx_packet_data,
    input wire [6:0] buffer_occupancy
);
endmodule
