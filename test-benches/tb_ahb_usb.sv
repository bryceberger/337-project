`default_nettype none `timescale 1ns / 10ps
`include "test-benches/ahb_bus.sv"
`include "test-benches/usb_bus.sv"

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
        STATUS_DATA = 'h1,
        STATUS_IN = 'h2,
        STATUS_OUT = 'h4,
        STATUS_ACK = 'h8,
        STATUS_NAK = 'h10,
        STATUS_RX = 'h100,
        STATUS_TX = 'h200;

    localparam bit [15:0] 
        TX_SEND_DATA = 'h1,
        TX_SEND_ACK = 'h2,
        TX_SEND_NAK = 'h3,
        TX_SEND_STALL = 'h4;

    // testbench signals
    int test_num;
    string test_case;
    string subtest_case;

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

    // USB idles high
    sequence TX_High; tx_dp == 1'b1 && tx_dm == 1'b0; endsequence
    sequence TX_Low; tx_dp == 1'b0 && tx_dm == 1'b1; endsequence
    sequence TX_Eop; tx_dp == tx_dm; endsequence
    sequence TX_nEop; tx_dp != tx_dm; endsequence
    sequence TX_Idle;
        ($stable(
            tx_dp
        ) && $stable(
            tx_dm
        )) [* 53: 57];
    endsequence

    sequence Sync;
        $fell(
            tx_dp
        ) && $rose(
            tx_dm
        ) ##0 (TX_Low [* 8: 10] ##1 TX_High [* 8: 10]) [* 3] ##1
            TX_Low [* 16: 20];
    endsequence

    /* verilog_format: off */
    sequence TokenPID;
        TX_Low [*8:10]                 // 1
        ##1 TX_High [*8:10]            // 0
        ##1 (
            (
                TX_Low [*8:10]         // 0
                ##1 TX_High [*8:10]    // 0
                ##1 TX_Low [*32:40]    // 0111
            ) or (
                TX_Low [*16:20]        // 01
                ##1 TX_High [*24:30]   // 011
                ##1 TX_Low [*8:10]     // 0
            )
        );
    endsequence

    sequence DataPID;
        TX_Low [*16:20]                // 11
        ##1 TX_High [*8:10]            // 0
        ##1 (
            (
                TX_Low [*8:10]         // 0
                ##1 TX_High [*8:10]    // 0
                ##1 TX_Low [*24:30]    // 011
            ) or (
                TX_High [*8:10]        // 1
                ##1 TX_Low [*8:10]     // 0
                ##1 TX_High [*16:20]   // 01
            )
        );
    endsequence

    sequence HandshakePID;
        TX_High [*16:20]               // 01
        ##1 (
            ( // ACK
                TX_Low [*8:10]         // 0
                ##1 TX_High [*16:20]   // 01
                ##1 TX_Low [*24:30]    // 011
            ) or ( // NAK
                TX_Low [*24:30]        // 011
                ##1 TX_High [*16:20]   // 01
                ##1 TX_Low [*8:10]     // 0
            ) or ( // STALL
                TX_High [*24:30]       // 111
                ##1 TX_Low [*8:10]     // 0
                ##1 TX_High [*8:10]    // 0
                ##1 TX_Low [*8:10]     // 0
            )
        );
    endsequence

    sequence CorrectTokenPacket;
        byte bit_count = 0;
        TX_nEop [*] ##1 TX_Eop [*] ##1 TX_nEop;
    endsequence

    sequence CorrectDataPacket;
        int bit_count;
        TX_nEop [*] ##1 TX_Eop [*] ##1 TX_nEop;
    endsequence

        property TestProperty;
        @(posedge clk) disable iff (!n_rst)
            $rose(d_mode) |-> ##[0:3] Sync ##1 HandshakePID ##[0:3] TX_Eop ##[16:20] !d_mode
        endproperty

    property BeginPacket;
        @(posedge clk) disable iff (!n_rst)
        $rose(d_mode) |-> (
            (##[0:3] Sync ##1 ( // good sync
                (TokenPID ##1 CorrectTokenPacket)
                or
                (DataPID ##1 CorrectDataPacket)
                or
                (HandshakePID ##1 (
                    ##[0:3] TX_Eop // immediate EOP
                    ##[16:20] !d_mode // transfer inactive
                ))
            ))
        )
    endproperty
    /* verilog_format: on */

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
        automatic int i = 0;
        if (expected.size() == 0) return;
        for (i = 0; i < expected.size() - 5; i += 4) begin
            a_bus.add(.addr(ADDR_DATA),
                      .data({
                          expected[i+3],
                          expected[i+2],
                          expected[i+1],
                          expected[i]
                      }));
        end
        a_bus.execute();
        for (int j = i; j < expected.size(); j++) begin
            a_bus.add(.addr(ADDR_DATA), .data({24'h0, expected[j]}), .size(0));
        end
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
        // Initialize Test Case Navigation Signals
        test_case = "Initialization";
        test_num  = -1;

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
        // Receiving USB Packets
        // **************************************************
        new_test("Receiving USB Packets");
        reset_dut();

        subtest_case = "Sending IN token (USB)";
        u_bus.enqueue_usb_token(1);
        u_bus.send_usb_packet();
        subtest_case = "Reading AHB Memory";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_IN));
        a_bus.execute();

        subtest_case = "Sending OUT token (USB)";
        u_bus.enqueue_usb_token(0);
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
                rng.num = 15;
                assert (rng.randomize() == 1);
                u_bus.enqueue_usb_data(.data(rng.data));
                u_bus.send_usb_packet();
            end
            begin
                // wait until actual data is being sent
                #(CLK_PERIOD * 200);
                subtest_case = "Reading data in progress";
                a_bus.add(.addr(ADDR_STATUS), .data(STATUS_RX));
                a_bus.execute();
            end
        join
        subtest_case = "Reading final buffer state";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_DATA));
        a_bus.add(.addr(ADDR_BUFFER_OCC), .data(rng.num));
        a_bus.execute();
        check_received_data(rng.data);
        subtest_case = "Flushing buffer";
        a_bus.add(.addr(ADDR_FLUSH_BUFFER), .data(1), .write(1), .size(0));
        a_bus.execute();
        #(CLK_PERIOD * 5);
        a_bus.add(.addr(ADDR_FLUSH_BUFFER), .data(0), .size(0));
        a_bus.add(.addr(ADDR_BUFFER_OCC), .data(0));
        a_bus.execute();

        @(posedge clk);
        @(negedge clk);
        subtest_case = "Sending 0 data";
        u_bus.enqueue_usb_data(.data({}));
        u_bus.send_usb_packet();
        subtest_case = "Reading AHB Memory";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_DATA));
        a_bus.add(.addr(ADDR_BUFFER_OCC), .data(0));
        a_bus.execute();
        a_bus.add(.addr(ADDR_FLUSH_BUFFER), .data(1), .write(1), .size(0));
        a_bus.execute();

        subtest_case = "Sending 64 data";
        rng.num      = 64;
        assert (rng.randomize() == 1);
        u_bus.enqueue_usb_data(.data(rng.data));
        u_bus.send_usb_packet();
        subtest_case = "Reading AHB Memory";
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_DATA));
        a_bus.add(.addr(ADDR_BUFFER_OCC), .data(64));
        a_bus.execute();
        check_received_data(rng.data);
        a_bus.add(.addr(ADDR_FLUSH_BUFFER), .data(1), .write(1), .size(0));
        a_bus.execute();

        // **************************************************
        // Sending USB Packets
        // **************************************************
        new_test("Sending USB Packets");
        reset_dut();

        // this will be verified good by the checker
        subtest_case = "Sending ACK";
        a_bus.add(.addr(ADDR_TX_CONTROL), .data(TX_SEND_ACK), .write(1));
        a_bus.execute();

        for (int i = 0; i < 10; i++) begin
            assert property (BeginPacket);
            @(posedge clk);
        end

        @(negedge d_mode);
        #(CLK_PERIOD * 10);
        subtest_case = "Sending NAK";
        a_bus.add(.addr(ADDR_TX_CONTROL), .data(TX_SEND_NAK), .write(1));
        a_bus.execute();

        for (int i = 0; i < 10; i++) begin
            assert property (BeginPacket);
            @(posedge clk);
        end

        // ensure that flag is high when transmitting
        #(CLK_PERIOD * 5);
        a_bus.add(.addr(ADDR_STATUS), .data(STATUS_TX));
        a_bus.execute();

        @(negedge d_mode);
        #(CLK_PERIOD * 10);
        subtest_case = "Sending STALL";
        a_bus.add(.addr(ADDR_TX_CONTROL), .data(TX_SEND_STALL), .write(1));
        a_bus.execute();

        for (int i = 0; i < 10; i++) begin
            assert property (BeginPacket);
            @(posedge clk);
        end

        subtest_case = "Sending data";
        rng.num      = 20;
        assert (rng.randomize() == 1);
        for (int i = 0; i < rng.data.size(); i += 4)
            a_bus.add(.addr(ADDR_DATA),
                      .data({
                          rng.data[i+3],
                          rng.data[i+2],
                          rng.data[i+1],
                          rng.data[i]
                      }),
                      .write(1));
        a_bus.add(.addr(ADDR_TX_CONTROL), .data(TX_SEND_DATA), .write(1));
        a_bus.execute();

        for (int i = 0; i < 10; i++) begin
            assert property (BeginPacket);
            @(posedge clk);
        end

    end
endmodule
