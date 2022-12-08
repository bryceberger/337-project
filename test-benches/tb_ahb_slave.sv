`default_nettype none `timescale 1ns / 10ps
`include "source/states.sv"
`include "test-benches/ahb_bus.sv"

class address_gen;
    bit write = 0;
    bit [1:0] size = 0;

    rand bit [3:0] addr1;
    rand bit [3:0] addr2;
    rand bit [31:0] data;

    constraint same {
        (size == 0) -> addr1 == addr2;
        (size == 1) -> addr1[3:1] == addr2[3:1];
        (size == 2) -> addr1[3:2] == addr2[3:2];
    }

    constraint align {
        (size == 1) -> addr1[0] == 0;
        (size == 2) -> addr1[1:0] == 0;
    }

    constraint valid_write {
        (write == 1 && size < 2) -> addr1 inside {[0 : 3], ['hc : 'hd]};
        (write == 1 && size >= 2) -> addr1 inside {[0 : 3], ['hc : 'hf]};
    }

    constraint invalid_write {
        (write == 1 && size == 0) -> addr1 inside {['h9 : 'hb], ['he : 'hf]};
        (write == 1 && size == 1) -> addr1 inside {['ha : 'hb], ['he : 'hf]};
        (write == 1 && size >= 2) -> addr1 inside {[4 : 'hb]};
    }

    constraint normal_register {addr1 inside {['h4 : 'hf]};}

    constraint write_to_cd {
        (addr1 == 'hc) -> data[31:16] == 0;
        (addr1 == 'hc) -> data[7] == 1;
        (addr1 == 'hd) -> data[31:8] == 0;
    }

    constraint data_size {
        (size == 0) -> data[31:7] == 0;
        (size == 1) -> data[31:16] == 0;
    }
endclass

module tb_ahb_slave ();
    // timing constants
    localparam time CLK_PERIOD = 10ns;

    // testbench signals
    int test_num;
    string test_case;
    string subtest_case;

    // general inputs
    logic clk, n_rst;
    // general outputs
    logic d_mode;
    // ahb inputs
    logic hsel;
    logic [3:0] haddr;
    logic [2:0] hburst;
    logic [1:0] hsize, htrans;
    logic hwrite;
    logic [31:0] hwdata;
    // ahb outputs
    logic [31:0] hrdata;
    logic hresp, hready;
    // rx inputs
    logic [3:0] rx_packet;
    logic rx_data_ready, rx_transfer_active, rx_error;
    // tx inputs
    logic tx_transfer_active, tx_error;
    // tx outputs
    logic [2:0] tx_packet;
    logic tx_start;
    // data buffer inputs
    logic [31:0] rx_data;
    logic [7:0] buffer_occupancy;
    // data buffer outputs
    logic [1:0] get_rx_data, store_tx_data;
    logic [31:0] tx_data;
    logic clear;

    address_gen rng;
    ahb_bus bus = new;

    assign bus.clk    = clk;
    assign hsel       = bus.hsel;
    assign haddr      = bus.haddr;
    assign htrans     = bus.htrans;
    assign hsize      = bus.hsize;
    assign hwrite     = bus.hwrite;
    assign hwdata     = bus.hwdata;
    assign bus.hrdata = hrdata;
    assign bus.hresp  = hresp;
    assign bus.hready = hready;

    ahb_slave DUT (.*);

    task reset_dut();
        n_rst = 1'b0;
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        n_rst = 1'b1;
        @(posedge clk);
        @(posedge clk);
    endtask

    task init_usb_inputs();
        {
            n_rst, rx_packet, rx_data_ready, rx_transfer_active, rx_error,
            tx_transfer_active, tx_error, rx_data, buffer_occupancy
        } = '0;
    endtask

    task new_test(string name = "");
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        test_case    = name;
        subtest_case = "";
        test_num     = test_num + 1;
    endtask

    /* svlint off keyword_forbidden_always */
    /* svlint off legacy_always */
    /* svlint off level_sensitive_always */
    always begin : CLK_GEN
        clk = 1'b0;
        #(CLK_PERIOD / 2.0);
        clk = 1'b1;
        #(CLK_PERIOD / 2.0);
    end
    /* svlint on level_sensitive_always */
    /* svlint on legacy_always */
    /* svlint on keyword_forbidden_always */

    initial begin
        $timeformat(-9, 2, " ns", 20);
        rng = new;
        rng.invalid_write.constraint_mode(0);

        // Initialize Test Case Navigation Signals
        test_case = "Initialization";
        test_num  = -1;
        init_usb_inputs();

        @(posedge clk);

        // **************************************************
        // Reset
        // **************************************************
        new_test("Power on / Reset");

        n_rst = 0;
        @(negedge clk);

        // all outputs should be initialized to 0
        assert ({
            d_mode, hrdata, hresp,
            tx_start, get_rx_data, store_tx_data,
            clear
        } == '0);

        // **************************************************
        // Basic Write / Read
        // **************************************************
        new_test("Isolated single read / write");
        buffer_occupancy   = 1;
        tx_transfer_active = 1;
        reset_dut();


        rng.write    = 1;

        subtest_case = "4 byte";
        rng.size     = 2;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(2));
        bus.execute(1);
        @(negedge clk);
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(2));
        bus.execute(1);

        @(negedge clk);
        subtest_case = "2 byte";
        rng.size     = 1;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(1));
        bus.execute(1);
        @(negedge clk);
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(1));
        bus.execute(1);

        @(negedge clk);
        subtest_case = "1 byte";
        rng.size     = 0;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(0));
        bus.execute(1);
        @(negedge clk);
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(0));
        bus.execute(1);

        new_test("Overlapping single read / write");

        subtest_case = "4 byte";
        rng.size     = 2;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(2));
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(2));
        bus.execute(2);

        @(negedge clk);
        subtest_case = "2 byte";
        rng.size     = 1;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(1));
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(1));
        bus.execute(2);

        @(negedge clk);
        subtest_case = "1 byte";
        rng.size     = 0;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(0));
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(0));
        bus.execute(2);

        rng.write_to_cd.constraint_mode(0);

        buffer_occupancy   = 0;
        tx_transfer_active = 0;

        // **************************************************
        // Bad Write
        // **************************************************
        new_test("Writing to read-only");
        reset_dut();

        rng.invalid_write.constraint_mode(1);
        rng.valid_write.constraint_mode(0);

        subtest_case = "4 byte";
        rng.size     = 2;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(2),
                .err(1));
        bus.add(.addr(rng.addr2), .data(0), .write(0), .size(2));
        bus.execute(2);

        subtest_case = "2 byte";
        rng.size     = 1;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(1),
                .err(1));
        bus.add(.addr(rng.addr2), .data(0), .write(0), .size(1));
        bus.execute(2);

        subtest_case = "1 byte";
        rng.size     = 0;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(0),
                .err(1));
        bus.add(.addr(rng.addr2), .data(0), .write(0), .size(0));
        bus.execute(2);

        rng.invalid_write.constraint_mode(0);
        rng.valid_write.constraint_mode(1);

        // wait out a few clock cycles before the final disable
        for (int i = 0; i < 20; i++) @(posedge clk);
        // disable CLK_GEN;
    end
endmodule
