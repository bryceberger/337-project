`default_nettype none `timescale 1ns / 10ps
`include "test-benches/ahb_a_bus.sv"
`include "test-benches/usb_a_bus.sv"

class rand_data;
    int num = 1;
    rand byte data[];
    constraint sizing {data.size == num;}
endclass

module tb_ahb_usb ();
    // timing constants
    localparam time CLK_PERIOD = (250 / 27) * 1ns;  // ≈ 9.27 ns --- 108 MHz

    rand_data rng = new;

    typedef enum bit [3:0] {
        ADDR_DATA = 'h0,
        ADDR_STATUS = 'h4,
        ADDR_ERR = 'h6,
        ADDR_BUFFER_OCC = 'h8,
        ADDR_TX_CONTROL = 'hc,
        ADDR_FLUSH_BUFFER = 'hd
    } addr_e;

    localparam bit [15:0] 
        STATUS_DATA = 'h0,
        STATUS_IN = 'h1,
        STATUS_OUT = 'h2,
        STATUS_ACK = 'h4,
        STATUS_NAK = 'h8,
        STATUS_RX = 'h10,
        STATUS_TX = 'h20;

    // general inputs
    logic clk, n_rst;
    // general outputs
    logic d_mode;
    // ahb inputs
    logic hsel, hwrite;
    logic [3:0] haddr;
    logic [2:0] hburst;
    logic [1:0] htrans, hsize;
    logic [31:0] hwdata;
    // ahb outputs
    logic [31:0] hrdata;
    logic hresp, hready;
    // rx inputs
    logic rx_dp, rx_dm;
    // tx outputs
    logic tx_dp, tx_dm;

    ahb_usb DUT (.*);

    ahb_bus a_bus = new;
    usb_bus u_bus = new;
    assign a_bus.clk    = clk;
    assign hsel         = a_bus.hsel;
    assign haddr        = a_bus.haddr;
    assign htrans       = a_bus.htrans;
    assign hsize        = a_bus.hsize;
    assign hwrite       = a_bus.hwrite;
    assign hwdata       = a_bus.hwdata;
    assign a_bus.hrdata = hrdata;
    assign a_bus.hresp  = hresp;
    assign a_bus.hready = hready;

    always_comb begin : USB_CONTROL_RX
        rx_dp = u_bus.dp;
        rx_dm = u_bus.dm;
    end

    always_comb begin : TX_CONTROL_USB
        u_bus.dp = tx_dp;
        u_bus.dm = tx_dm;
    end

    task reset_dut();
        n_rst = 1'b0;
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        n_rst = 1'b1;
        @(posedge clk);
        @(posedge clk);
    endtask

    task check_received_data(input byte expected[]);
        if (expected.size() == 0) return;
        int i = 0;
        for (; i < expected.size() - 4; i += 4)
            a_bus.add(.addr(ADDR_DATA),
                      .data({
                          expected[i+3],
                          expected[i+2],
                          expected[i+1],
                          expected[i]
                      }));
        for (; i < expected.size(); i++)
            a_bus.add(.addr(ADDR_DATA), .data(expected[i]), .size(0));
        a_bus.execute();
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
        disable TX_CONTROL_USB;
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
        assert ({d_mode, hrdata, hresp} == '0)
        else $error("Outputs not zero after reset");

        // **************************************************
        // Send USB Packets
        // **************************************************
        new_test("Sending USB Packets");
        reset_dut();

        subtest_case = "Sending IN token (USB)";
        u_bus.enqueue_usb_token(0);
        u_bus.send_usb_packet();
        subtest_case = "Reading AHB Memory";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_IN));
        a_bus.execute();

        subtest_case = "Sending OUT token (USB)";
        u_bus.enqueue_usb_token(1);
        u_bus.send_usb_packet();
        subtest_case = "Reading AHB Memory";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_OUT));
        a_bus.execute();

        subtest_case = "Sending ACK handshake (USB)";
        // send packet
        u_bus.enqueue_usb_handshake(0);
        u_bus.send_usb_packet();
        subtest_case = "Reading AHB Memory";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_ACK));
        a_bus.execute();

        subtest_case = "Sending NAK handshake (USB)";
        u_bus.enqueue_usb_handshake(1);
        u_bus.send_usb_packet();
        subtest_case = "Reading AHB Memory";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_NAK));
        a_bus.execute();

        subtest_case = "Sending 15 data";
        fork : REC_DATA_TEST
            begin
                rng.size = 15;
                rng.randomize();
                u_bus.enqueue_usb_data(.data(rng.data));
                u_bus.send_usb_packet();
            end
            begin
                // wait until actual data is being sent
                #(CLK_PERIOD * 200);
                a_bus.add(.addr(ADDR_STATUS), .data(STATUS_RX));
                a_bus.execute();
            end
        join
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_DATA));
        a_bus.add(.addr(ADDR_BUFFER_OCC), .data(rng.size));
        a_bus.execute();
        check_received_data(rng.data);

        subtest_case = "Sending 0 data";
        u_bus.enqueue_usb_data(.data({}));
        u_bus.send_usb_packet();
        subtest_case = "Reading AHB Memory";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_DATA));
        a_bus.add(.addr(ADDR_BUFFER_OCC), .data(0));
        a_bus.execute();

        subtest_case = "Sending 64 data";
        rng.size     = 64;
        rng.randomize();
        u_bus.enqueue_usb_data(.data(rng.data));
        u_bus.send_usb_packet();
        subtest_case = "Reading AHB Memory";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_DATA));
        a_bus.add(.addr(ADDR_BUFFER_OCC), .data(64));
        a_bus.execute();
        check_received_data(rng.data);
    end

endmodule
