`default_nettype none `timescale 1ns / 10ps

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
endclass

module tb_ahb_slave ();
    // timing constants
    localparam time CLK_PERIOD = 10ns;
    // Sizing related constants
    localparam int DATA_WIDTH = 2;
    localparam int ADDR_WIDTH = 4;
    localparam int DATA_WIDTH_BITS = DATA_WIDTH * 8;
    localparam int DMB = DATA_WIDTH_BITS - 1;
    localparam int AMB = ADDR_WIDTH - 1;
    // general constants
    localparam bit VERBOSE = 0;

    // testbench signals
    int test_num;
    string test_case;
    string subtest_case;

    // expected outputs
    logic [31:0] expected_hrdata;
    logic expected_hresp, expected_hready;

    // needed to control ahb bus model
    logic
        enqueue_transaction,
        transaction_write,
        transaction_fake,
        transaction_error,
        current_transaction_error,
        enable_transactions,
        model_reset;
    logic [2:0] transaction_size;
    logic [AMB:0] transaction_addr;
    logic [DMB:0] transaction_data;
    int current_transaction_num;

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
    logic clear_data_buffer;

    ahb_slave DUT (.*);

    ahb_lite_bus BFM (.*);

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

    /* default:
     * for device
     * read
     * address 0
     * data 0
     * no error
     * 16 bits
     */
    task queue(bit for_dut = 1, bit write = 0, bit [AMB:0] address = 0,
               bit [DMB:0] data = 0, bit expected_error = 0,
               bit [1:0] size = 2);
        // Make sure enqueue flag is low (will need a 0->1 pulse later)
        enqueue_transaction = 1'b0;

        // Setup info about transaction
        transaction_fake    = ~for_dut;
        transaction_write   = write;
        transaction_addr    = address;
        transaction_data    = data;
        transaction_error   = expected_error;
        transaction_size    = {2'b00, size};

        // Pulse the enqueue flag
        #0.1ns;
        enqueue_transaction = 1'b1;
        #0.1ns;
        enqueue_transaction = 1'b0;
    endtask

    task execute_transactions(int num_transactions = 1);
        // Activate the bus model
        enable_transactions = 1'b1;
        @(posedge clk);

        // Process the transactions (all but last one overlap 1 out of 2 cycles
        for (int wait_var = 0; wait_var < num_transactions; wait_var++) begin
            @(posedge clk);
        end

        // Run out the last one (currently in data phase)
        @(posedge clk);

        // Turn off the bus model
        @(negedge clk);
        enable_transactions = 1'b0;
    endtask

    task new_test(string name = "");
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        test_case    = name;
        subtest_case = "";
        test_num     = test_num + 1;
        init_fir_side();
        init_expected_outs();
    endtask

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

    initial begin
        address_gen rng = new;
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
            d_mode, hrdata, hresp, hready,
            tx_packet, tx_start, get_rx_data, store_tx_data, tx_data,
            clear_data_buffer
        } == '0);

        // **************************************************
        // Basic Write / Read
        // **************************************************
        new_test("Isolated single read / write");
        reset_dut();

        rng.write    = 1;

        subtest_case = "4 byte";
        rng.size     = 2;
        assert (rng.randomize() == 1);
        queue(.address(rng.addr1), .data(rng.data), .write(1), .size(2));
        execute_transactions(1);
        @(negedge clk);
        queue(.address(rng.addr2), .data(rng.data), .write(0), .size(2));
        execute_transactions(1);

        @(negedge clk);
        subtest_case = "2 byte";
        rng.size     = 1;
        assert (rng.randomize() == 1);
        queue(.address(rng.addr1), .data(rng.data), .write(1), .size(1));
        execute_transactions(1);
        @(negedge clk);
        queue(.address(rng.addr2), .data(rng.data), .write(0), .size(1));
        execute_transactions(1);

        @(negedge clk);
        subtest_case = "1 byte";
        rng.size     = 0;
        assert (rng.randomize() == 1);
        queue(.address(rng.addr1), .data(rng.data), .write(1), .size(0));
        execute_transactions(1);
        @(negedge clk);
        queue(.address(rng.addr2), .data(rng.data), .write(0), .size(0));
        execute_transactions(1);

        new_test("Overlapping single read / write");

        subtest_case = "4 byte";
        rng.size     = 2;
        assert (rng.randomize() == 1);
        queue(.address(rng.addr1), .data(rng.data), .write(1), .size(2));
        queue(.address(rng.addr2), .data(rng.data), .write(0), .size(2));
        execute_transactions(2);

        @(negedge clk);
        subtest_case = "2 byte";
        rng.size     = 1;
        assert (rng.randomize() == 1);
        queue(.address(rng.addr1), .data(rng.data), .write(1), .size(1));
        queue(.address(rng.addr2), .data(rng.data), .write(0), .size(1));
        execute_transactions(2);

        @(negedge clk);
        subtest_case = "1 byte";
        rng.size     = 0;
        assert (rng.randomize() == 1);
        queue(.address(rng.addr1), .data(rng.data), .write(1), .size(0));
        queue(.address(rng.addr2), .data(rng.data), .write(0), .size(0));
        execute_transactions(2);

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
        queue(.address(rng.addr1), .data(rng.data), .write(1), .size(2),
              .err(1));
        queue(.address(rng.addr2), .data(0), .write(0), .size(2));
        execute_transactions(2);

        subtest_case = "2 byte";
        rng.size     = 1;
        assert (rng.randomize() == 1);
        queue(.address(rng.addr1), .data(rng.data), .write(1), .size(1),
              .err(1));
        queue(.address(rng.addr2), .data(0), .write(0), .size(1));
        execute_transactions(2);

        subtest_case = "1 byte";
        rng.size     = 0;
        assert (rng.randomize() == 1);
        queue(.address(rng.addr1), .data(rng.data), .write(1), .size(0),
              .err(1));
        queue(.address(rng.addr2), .data(0), .write(0), .size(0));
        execute_transactions(2);

        rng.invalid_write.constraint_mode(0);
        rng.valid_write.constraint_mode(1);

        // wait out a few clock cycles before the final disable
        for (int i = 0; i < 20; i++) @(posedge clk);
    end

    final disable CLK_GEN;
endmodule
