`default_nettype none `timescale 1ns / 10ps

class rand_data;
    static int num = 1;
    rand byte data[];
    bit [31:0] pak = 0;
    constraint sizing {data.size == num;}

    function void post_randomize();
        if (data.size >= 4) this.pak = {data[3], data[2], data[1], data[0]};
    endfunction
endclass

module tb_data_buffer ();
    // timing constants
    localparam time CLK_PERIOD = 10ns;

    // testbench signals
    int test_num;
    string test_case;
    string subtest_case;

    rand_data rng = new;

    // general inputs
    logic clk, n_rst, flush, clear;
    // general outputs
    logic [6:0] buffer_occ;
    // rx inputs
    logic [1:0] get_rx_data;
    logic store_rx_data;
    logic [7:0] rx_data_in;
    // rx outputs
    logic [31:0] rx_data_out;
    // tx inputs
    logic get_tx_data;
    logic [1:0] store_tx_data;
    logic [31:0] tx_data_in;
    // tx outputs
    logic [7:0] tx_data_out;

    data_buffer DUT (.*);

    task reset_dut();
        n_rst = 1'b0;
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        n_rst = 1'b1;
        @(posedge clk);
        @(posedge clk);
    endtask

    task init_inputs();
        {
            flush, clear,
            get_rx_data, store_rx_data, rx_data_in,
            get_tx_data, store_tx_data, tx_data_in
        } = '0;
    endtask

    task fill_usb(input byte data[]);
        if (data.size() == 0) return;
        @(negedge clk);
        store_rx_data = 1;
        for (int i = 0; i < data.size(); i++) begin
            rx_data_in = data[i];
            @(posedge clk);
        end
        @(negedge clk);
        store_rx_data = 0;
        rx_data_in    = 0;
    endtask

    task drain_usb(input byte expected_data[]);
        if (expected_data.size() == 0) return;
        @(negedge clk);
        get_tx_data = 1;
        for (int i = 0; i < expected_data.size(); i++) begin
            assert (expected_data[i] == tx_data_out)
            else
                $error(
                    "Incorrect tx_data_out response at time %t (expected 0x%02x, got 0x%02x)",
                    $time,
                    expected_data[i],
                    tx_data_out
                );
            if (i == expected_data.size() - 1) break;
            @(posedge clk);
            @(negedge clk);
        end
        @(negedge clk);
        get_tx_data = 0;
    endtask

    task fill_ahb(input byte data[], input bit [1:0] size = 3);
        int shift;
        if (data.size() == 0) return;

        if (size == 0) size = 1;

        if (size == 1) shift = 1;
        else if (size == 2) shift = 2;
        else shift = 4;

        @(negedge clk);
        store_tx_data = size;
        for (int i = 0; i < data.size(); i += shift) begin
            tx_data_in = {data[i+3], data[i+2], data[i+1], data[i]};
            @(posedge clk);
        end
        @(negedge clk);
        store_tx_data = 0;
        tx_data_in    = 0;
    endtask

    task drain_ahb(input byte expected_data[], input bit [1:0] size = 3);
        int shift;
        if (expected_data.size() == 0) return;

        if (size == 0) size = 1;

        if (size == 1) shift = 1;
        else if (size == 2) shift = 2;
        else shift = 4;

        @(negedge clk);
        get_rx_data = size;
        for (int i = 0; i < expected_data.size(); i += shift) begin
            assert ({
                expected_data[i+3], expected_data[i+2],
                expected_data[i+1], expected_data[i]
            } == rx_data_out)
            else
                $error(
                    "Incorrect rx_data_out response at time %t (expected 0x%08x, got 0x%08x)",
                    $time,
                    {
                        expected_data[i+3],
                        expected_data[i+2],
                        expected_data[i+1],
                        expected_data[i]
                    },
                    rx_data_out
                );
            if (i + shift >= expected_data.size()) break;
            @(posedge clk);
            @(negedge clk);
        end
        @(negedge clk);
        get_rx_data = 0;
    endtask

    task new_test(string name = "");
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        test_case    = name;
        subtest_case = "";
        test_num     = test_num + 1;
    endtask

    task check_outputs(bit [31:0] expected_data);
        @(negedge clk);
        assert (rx_data_out[7:0] == tx_data_out)
        else
            $error(
                "rx_data_out and tx_data_out mismatch at time %t (rx = 0x%02x, tx = 0x%02x)",
                $time,
                rx_data_out[7:0],
                tx_data_out
            );

        assert (rx_data_out == expected_data)
        else
            $error(
                "Incorrect rx_data_out at time %t (expected 0x%08x, got 0x%08x)",
                $time,
                expected_data,
                rx_data_out
            );
        @(negedge clk);
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
        rng       = new;

        // Initialize Test Case Navigation Signals
        test_case = "Initialization";
        test_num  = -1;
        init_inputs();

        @(posedge clk);

        // **************************************************
        // Reset
        // **************************************************
        new_test("Power on / Reset");

        n_rst = 0;
        @(negedge clk);

        // all outputs should be initialized to 0
        assert ({buffer_occ, rx_data_out, tx_data_out} == '0);

        // **************************************************
        // Filling
        // **************************************************
        new_test("Filling from USB RX");

        subtest_case = "Single byte";
        reset_dut();
        rng.num = 1;
        assert (rng.randomize() == 1);
        fill_usb(rng.data);
        check_outputs({8'h0, 8'h0, 8'h0, rng.data[0]});

        subtest_case = "Multiple bytes";
        reset_dut();
        rng.num = 20;
        assert (rng.randomize() == 1);
        fill_usb(rng.data);
        check_outputs(rng.pak);

        subtest_case = "Max bytes";
        reset_dut();
        rng.num = 64;
        assert (rng.randomize() == 1);
        fill_usb(rng.data);
        check_outputs(rng.pak);

        new_test("Filling from AHB-lite");

        subtest_case = "Single byte";
        reset_dut();
        rng.num = 1;
        assert (rng.randomize() == 1);
        fill_ahb(rng.data);
        check_outputs({8'h0, 8'h0, 8'h0, rng.data[0]});

        subtest_case = "Multiple bytes";
        reset_dut();
        rng.num = 20;
        assert (rng.randomize() == 1);
        fill_ahb(rng.data);
        check_outputs(rng.pak);

        subtest_case = "Max bytes";
        reset_dut();
        rng.num = 64;
        assert (rng.randomize() == 1);
        fill_ahb(rng.data);
        check_outputs(rng.pak);

        // **************************************************
        // Draining
        // **************************************************
        new_test("Draining from USB TX");

        subtest_case = "Single byte";
        reset_dut();
        rng.num = 1;
        assert (rng.randomize() == 1);
        fill_ahb(rng.data);
        drain_usb(rng.data);
        check_outputs(0);

        subtest_case = "Multiple bytes";
        reset_dut();
        rng.num = 20;
        assert (rng.randomize() == 1);
        fill_ahb(rng.data);
        drain_usb(rng.data);
        check_outputs(0);

        subtest_case = "Max bytes";
        reset_dut();
        rng.num = 64;
        assert (rng.randomize() == 1);
        fill_ahb(rng.data);
        drain_usb(rng.data);
        check_outputs(0);

        new_test("Draining from AHB-lite");

        subtest_case = "Single byte";
        reset_dut();
        rng.num = 1;
        assert (rng.randomize() == 1);
        fill_usb(rng.data);
        drain_ahb(rng.data);
        check_outputs(0);

        subtest_case = "Multiple bytes";
        reset_dut();
        rng.num = 20;
        assert (rng.randomize() == 1);
        fill_usb(rng.data);
        drain_ahb(rng.data);
        check_outputs(0);

        subtest_case = "Max bytes";
        reset_dut();
        rng.num = 64;
        assert (rng.randomize() == 1);
        fill_usb(rng.data);
        drain_ahb(rng.data);
        check_outputs(0);

        new_test("Done");
        // wait out a few clock cycles before the final disable
        for (int i = 0; i < 20; i++) @(posedge clk);
        disable CLK_GEN;
    end
endmodule
