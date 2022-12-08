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
    input var [2:0] rx_packet,
    input var rx_data_ready,
    input var rx_transfer_active,
    input var rx_error,
    // tx inputs
    input var tx_transfer_active,
    input var tx_error,
    // tx outputs
    output var [1:0] tx_packet,
    output var tx_start,
    // data buffer inputs
    input var [31:0] rx_data,
    input var [6:0] buffer_occupancy,
    // data buffer outputs
    output var [1:0] get_rx_data,
    output var [1:0] store_tx_data,
    output var [31:0] tx_data,
    output var clear
);

    // address mapping
    // 0x0: 4 R/W data buffer
    // 0x4: 2 R   status register
    // 0x6: 2 R   error register
    // 0x8: 1 R   buffer occupancy
    // 0xC: 1 R/W TX packet control
    // 0xD: 1 R/W flush buffer control 
    // 0xE: reserved
    // 0xF: reserved
    logic [7:0] mem    [17:0];
    logic [1:0] size;
    logic       write;
    logic [3:0] addr;
    logic       enable;

    assign enable    = hsel && htrans != IDLE;
    assign d_mode    = tx_transfer_active;
    assign tx_packet = mem['hc][2:0] - 1;
    assign tx_start  = |mem['hc];
    assign tx_data   = hwdata;
    assign clear     = |mem['hd];

    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) get_rx_data <= 0;
        else get_rx_data <= enable && !hwrite && addr == 0 ? hsize + 1 : 0;

    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) store_tx_data <= 0;
        else store_tx_data <= enable && hwrite && addr == 0 ? hsize + 1 : 0;

    logic prev_transfer;
    logic transfer_falling;
    assign transfer_falling = prev_transfer && !rx_transfer_active;
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) prev_transfer <= 0;
        else prev_transfer <= rx_transfer_active;

    logic clear_status;
    assign clear_status = (addr == 4 && !write);
    /* svlint off sequential_block_in_always_ff */  // only assigning to mem
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) mem <= '{18{0}};
        else begin
            mem['h4] <= {
                3'h0,
                transfer_falling ? rx_packet == 3 : clear_status ? 1'b0 : mem['hc][4], // nack
                transfer_falling ? rx_packet == 2 : clear_status ? 1'b0 : mem['hc][3], // ack
                transfer_falling ? rx_packet == 0 : clear_status ? 1'b0 : mem['hc][2], // out
                transfer_falling ? rx_packet == 1 : clear_status ? 1'b0 : mem['hc][1], // in
                rx_data_ready ? 1'b1 : rx_transfer_active || clear_status ? 1'b0 : mem['hc][0]
            };
            mem['h5] <= {6'h0, tx_transfer_active, rx_transfer_active};
            mem['h6] <= {7'h0, rx_error};
            mem['h7] <= {7'h0, tx_error};
            mem['h8] <= buffer_occupancy;

            if (buffer_occupancy == 0) mem['hd] <= 0;
            else mem['hd] <= mem['hd];

            // give tx_transfer_active a clock cycle to go high
            if (mem['hc][7] && tx_transfer_active) mem['hc] <= 0;
            else if (mem['hc]) mem['hc] <= {1'b1, mem['hc][6:0]};
            else mem['hc] <= mem['hc];

            // write if necessary
            /* svlint off explicit_if_else */
            if (enable && write && !hresp && addr != 0) begin
                mem[addr] <= hwdata[7:0];
                if (size != 0) mem[addr+1] <= hwdata[15:8];
                if (size > 1) {mem[addr+3], mem[addr+2]} <= hwdata[31:16];
            end
            /* svlint on explicit_if_else */
        end
    /* svlint on sequential_block_in_always_ff */

    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) hresp <= 0;
        else
            casez ({
                enable, hwrite, hsize, haddr
            })
                'b0???????: hresp <= 0;
                'b1?11????: hresp <= 1;  // 8 byte accesses not supported
                'b1?0?111?: hresp <= 1;  // 1 / 2 byte accesses to 0xE, 0xF
                'b1?0?101?: hresp <= 1;  // 1 / 2 byte accesses to 0xA, 0xB
                'b1?001001: hresp <= 1;  // 1 byte accesses to 0x9
                'b11??01??: hresp <= 1;  // write to 0x4 -- 0x7
                'b11??10??: hresp <= 1;  // write to 0x8 -- 0xB
                default: hresp <= 0;
            endcase

    // on err, hold ready low until receive acknowledge
    // make an actual error signal that is sure to stay high for a clock cycle
    // because if the bus is always in idle mode, err goes low after next rising
    // which means the write still goes through
    /*
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) hready <= 0;
        else hready <= !(hresp && htrans != IDLE);
	*/
    assign hready = !(hresp && enable);

    // address decoding
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) addr <= 0;
        else if (!enable) addr <= 0;
        else if (haddr < 4) addr <= 0;
        else
            case (hsize)
                'b00:    addr <= haddr;
                'b01:    addr <= {haddr[3:1], 1'b0};
                default: addr <= {haddr[3:2], 2'b0};
            endcase

    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) {size, write} <= 0;
        else {size, write} <= {hsize, hwrite};

    // have to set like this because otherwise would have to delay a cycle
    // upon reading 0x0 twice in a row
    // basically, read 0x0 directly from fifo (don't even have to store in mem)
    logic [31:0] read_source;
    always_comb
        if (addr == 0) read_source = rx_data;
        else read_source = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) hrdata <= 0;
        else if (!enable) hrdata <= 0;
        else if (hsel && !hwrite)
            case (hsize)
                'b00:    hrdata <= {24'b0, read_source[7:0]};
                'b01:    hrdata <= {16'b0, read_source[15:0]};
                default: hrdata <= read_source;
            endcase
        else hrdata <= 0;

endmodule
