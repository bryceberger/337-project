`default_nettype none
`include "source/states.sv"

module ahb_slave (
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
    input var [3:0] rx_packet,
    input var rx_data_ready,
    input var rx_transfer_active,
    input var rx_error,
    // tx inputs
    input var tx_transfer_active,
    input var tx_error,
    // tx outputs
    output var [2:0] tx_packet,
    output var tx_start,
    // data buffer inputs
    input var [31:0] rx_data,
    input var [7:0] buffer_occupancy,
    // data buffer outputs
    output var [1:0] get_rx_data,
    output var [1:0] store_tx_data,
    output var [31:0] tx_data,
    output var clear_data_buffer
);

    clocking ce @(posedge clk, negedge n_rst);
    endclocking

    // address mapping
    // 0x0: 4 R/W data buffer
    // 0x4: 2 R   status register
    // 0x6: 2 R   error register
    // 0x8: 1 R   buffer occupancy
    // 0xC: 1 R/W TX packet control
    // 0xD: 1 R/W flush buffer control 
    // 0xE: reserved
    // 0xF: reserved
    logic [7:0] mem   [15:0];
    logic [1:0] size;
    logic       write;
    logic [3:0] addr;

    /* svlint off sequential_block_in_always_ff */  // only assigning to mem
    always_ff @(ce)
        if (!n_rst) mem <= '{16{0}};
        else begin
            mem['h4] <= {
                4'h0,
                rx_packet == NACK,
                rx_packet == ACK,
                rx_packet == OUT,
                rx_packet == IN
            };
            mem['h5] <= {6'h0, tx_transfer_active, rx_transfer_active};
            mem['h6] <= {7'h0, rx_error};
            mem['h7] <= {7'h0, tx_error};
            mem['h8] <= buffer_occupancy;
            mem['hd] <= buffer_occupancy != 0 ? mem['hd] : 0;

            // give tx_transfer_active a clock cycle to go high
            if (mem['hc][7] && !tx_transfer_active) mem['hc] <= 0;
            else if (mem['hc]) mem['hc] <= {1'b1, mem['hc][6:0]};

            // write if necessary
            if (hsel && write && !hresp && addr != 0) begin
                mem[addr] <= hwdata[7:0];
                if (size != 0) mem[addr+1] <= hwdata[15:8];
                else if (size > 1) {mem[addr+3], mem[addr+2]} <= hwdata[31:16];
            end
        end
    /* svlint on sequential_block_in_always_ff */

    always_comb
        casez ({
            hwrite, hsize, haddr
        })
            'b?11????: hresp = 1;  // 8 byte accesses not supported
            'b?0?111?: hresp = 1;  // 1 / 2 byte accesses to 0xE, 0xF
            'b?0?101?: hresp = 1;  // 1 / 2 byte accesses to 0xA, 0xB
            'b?001001: hresp = 1;  // 1 byte accesses to 0x9
            'b1??01??: hresp = 1;  // write to 0x4 -- 0x7
            'b1??10??: hresp = 1;  // write to 0x8 -- 0xB
            default:   hresp = 0;
        endcase

    // on err, hold ready low until receive acknowledge
    assign hready = !(hresp && htrans != IDLE);

    // address decoding
    always_ff @(ce)
        if (!n_rst) addr <= 0;
        else if (haddr < 4) addr <= 0;
        else
            case (hsize)
                'b00:    addr <= haddr;
                'b01:    addr <= {haddr[3:1], 1'b0};
                default: addr <= {haddr[3:2], 2'b0};
            endcase

    always_ff @(ce)
        if (!n_rst) {size, write} <= 0;
        else {size, write} <= {hsize, hwrite};

    // have to set like this because otherwise would have to delay a cycle
    // upon reading 0x0 twice in a row
    // basically, read 0x0 directly from fifo (don't even have to store in mem)
    logic [31:0] read_source;
    always_comb
        if (addr == 0) read_source = rx_data;
        else read_source = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
    always_ff @(ce)
        if (!n_rst) hrdata <= 0;
        else if (hsel && !hwrite)
            case (hsize)
                'b00:    hrdata <= {24'b0, read_source[7:0]};
                'b01:    hrdata <= {16'b0, read_source[15:0]};
                default: hrdata <= read_source;
            endcase
        else hrdata <= 0;

endmodule
