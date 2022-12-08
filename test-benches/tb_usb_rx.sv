`timescale 1ns/10ps

`include "test-benches/tb_usb_transmit.sv"

module tb_usb_rx();

// Local Constants
localparam CHECK_DELAY = 1ns;
localparam CLK_PERIOD = (250/27) * 1ns; // ≈ 9.27 ns --- 108 MHz

localparam [3:0] IN_PID     = 4'b0001;
localparam [3:0] OUT_PID    = 4'b1001;
localparam [3:0] DATA0_PID  = 4'b0011;
localparam [3:0] DATA1_PID  = 4'b1011;
localparam [3:0] ACK_PID    = 4'b0010;
localparam [3:0] NAK_PID    = 4'b1010;
localparam [3:0] STALL_PID  = 4'b1110;

// Test Bench DUT Port Signals
reg clk, n_rst;
// USB input lines
reg dp, dm;
// Outputs to AHB-lite interface
wire [2:0] rx_packet;
wire rx_data_ready, rx_transfer_active, rx_error;
// I/O from FIFO
wire flush, store_rx_packet_data;
wire [7:0] rx_packet_data;
reg [6:0] buffer_occupancy;

// Test Bench Expected Signals
logic [2:0] expected_rx_packet;
logic expected_rx_data_ready;
logic expected_rx_transfer_active;
logic expected_rx_error;
logic expected_flush;
logic expected_store_rx_packet_data;
logic [7:0] expected_rx_packet_data;

// Test Bench Verification Signals
int test_num;
string test_case;

// Task for Resetting DUT
task reset_dut();
    // Activate reset signal
    n_rst = 1'b0;

    // Wait 2 clock cycles
    @(posedge clk);
    @(posedge clk);

    // Release reset signal away from clock's posedge
    @(negedge clk);
    n_rst = 1'b1;

    // Wait
    @(negedge clk);
endtask

`define info(mesg) $info("Test case %02d: %s", test_num, mesg)
`define error(mesg, got, exp) $error( \
        "Test case %02d: %s (got %d, expected %d)", \
        test_num, mesg, got, exp \
    )

task check_outputs(string check);
    /* reg [2:0] rx_packet; */
    assert(rx_packet == expected_rx_packet)
        `info("correct rx_packet");
    else
        `error("incorrect rx_packet", rx_packet, expected_rx_packet);
    /* reg rx_data_ready; */
    assert(rx_data_ready == expected_rx_data_ready)
        `info("correct rx_data_ready");
    else
        `error("rx_data_ready", rx_data_ready, expected_rx_data_ready);
    /* reg rx_transfer_active */
    assert(rx_transfer_active == expected_rx_transfer_active)
        `info("correct rx_transfer_active");
    else
        `error(
            "rx_transfer_active",
            rx_transfer_active, expected_rx_transfer_active
        );
    /* reg rx_error; */
    assert(rx_error == expected_rx_error)
        `info("correct rx_error");
    else
        `error("rx_error", rx_error, expected_rx_error);
    /* reg flush; */
    assert(flush == expected_flush)
        `info("correct flush");
    else
        `error("flush", flush, expected_flush);
    /* reg store_rx_packet_data; */
    assert(store_rx_packet_data == expected_store_rx_packet_data)
        `info("correct store_rx_packet_data");
    else
        `error(
            "store_rx_packet_data",
            store_rx_packet_data, expected_store_rx_packet_data
        );
    /* reg [7:0] rx_packet_data; */
    assert(rx_packet_data == expected_rx_packet_data)
        `info("correct rx_packet_data");
    else
        `error("rx_packet_data", rx_packet_data, expected_rx_packet_data);
endtask

// Clock Gen Block
always begin: CLK_GEN
    clk = 1'b0;
    #(CLK_PERIOD / 2.0);
    clk = 1'b1;
    #(CLK_PERIOD / 2.0);
end

sequence High; // USB idles high
    dp == 1'b1 && dm == 1'b0;
endsequence
sequence Low;
    dp == 1'b0 && dm == 1'b1;
endsequence
sequence EOP;
    dp == dm;
endsequence
sequence nEOP;
    dp != dm;
endsequence

sequence Idle;
    ($stable(dp) && $stable(dm)) [*53:57];
endsequence

property TransferActive;
    @(posedge clk) disable iff (!n_rst)
    rx_transfer_active |-> (
        (nEOP ##1 rx_transfer_active == 1'b1)
        or
        (EOP ##[7:12] rx_transfer_active == 1'b0)
        or
        (Idle ##1 rx_transfer_active == 1'b0)
    )
endproperty

property TransferInactive;
    @(posedge clk) disable iff (!n_rst)
    rx_transfer_active != 1'b1 |-> (
        ((High or EOP) ##1 rx_transfer_active == 1'b0)
        or
        (Low ##1 (
            (##[0:3] rx_transfer_active == 1'b1)
            and
            (##[0:3] flush == 1'b1 ##[1:2] flush == 1'b0)
        ))
    )
endproperty

sequence Sync;
    $fell(dp) && $rose(dm)
    ##0 (Low [*8:10] ##1 High [*8:10]) [*3] // 6 zeros
    ##1 Low [*16:20]; // 01
endsequence

sequence TokenPID;
    Low [*8:10]                 // 1
    ##1 High [*8:10]            // 0
    ##1 (
        (
            Low [*8:10]         // 0
            ##1 High [*8:10]    // 0
            ##1 Low [*32:40]    // 0111
        ) or (
            Low [*16:20]        // 01
            ##1 High [*24:30]   // 011
            ##1 Low [*8:10]     // 0
        )
    );
endsequence

sequence DataPID;
    Low [*16:20]                // 11
    ##1 High [*8:10]            // 0
    ##1 (
        (
            Low [*8:10]         // 0
            ##1 High [*8:10]    // 0
            ##1 Low [*24:30]    // 011
        ) or (
            High [*8:10]        // 1
            ##1 Low [*8:10]     // 0
            ##1 High [*16:20]   // 01
        )
    );
endsequence

sequence HandshakePID;
    High [*16:20]               // 01
    ##1 (
        ( // ACK
            Low [*8:10]         // 0
            ##1 High [*16:20]   // 01
            ##1 Low [*24:30]    // 011
        ) or ( // NAK
            Low [*24:30]        // 011
            ##1 High [*16:20]   // 01
            ##1 Low [*8:10]     // 0
        ) or ( // STALL
            High [*24:30]       // 111
            ##1 Low [*8:10]     // 0
            ##1 High [*8:10]    // 0
            ##1 Low [*8:10]     // 0
        )
    );
endsequence

property CorrectTokenPacket;
    byte bit_count = 0;
    nEOP [*] ##1 EOP [*] ##1 nEOP
    /* first_match( */
    /*     Low    [* 8:10] ##1 (High or EOP, bit_count += 1) */
    /*     or Low [*16:20] ##1 (High or EOP, bit_count += 2) */
    /*     or Low [*24:30] ##1 (High or EOP, bit_count += 3) */
    /*     or Low [*32:40] ##1 (High or EOP, bit_count += 4) */
    /*     or Low [*41:49] ##1 (High or EOP, bit_count += 5) */
    /*     or Low [*50:59] ##1 (High [*8:10], bit_count += 6) */
    /*     or High [* 8:10] ##1 (Low or EOP, bit_count += 1) */
    /*     or High [*16:20] ##1 (Low or EOP, bit_count += 2) */
    /*     or High [*24:30] ##1 (Low or EOP, bit_count += 3) */
    /*     or High [*32:40] ##1 (Low or EOP, bit_count += 4) */
    /*     or High [*41:49] ##1 (Low or EOP, bit_count += 5) */
    /*     or High [*50:59] ##1 (Low [*8:10], bit_count += 6) */
    /* ) [*] ##1 EOP #-# bit_count == 16; */
endproperty

property CorrectDataPacket;
    int bit_count;
    nEOP [*] ##1 EOP [*] ##1 nEOP
endproperty

property BeginPacket;
    @(posedge clk) disable iff (!n_rst)
    (!rx_transfer_active and Low) |-> (
        (Sync |=> ( // good sync
            (TokenPID |-> CorrectTokenPacket)
            and
            (DataPID |-> CorrectDataPacket)
            and
            (HandshakePID |=> (
                ##[0:3] EOP // immediate EOP
                ##12 !rx_transfer_active // transfer inactive
            ))
            or // --- OR ---
            (not (TokenPID or DataPID or HandshakePID)) // bad PID
            and
            (!rx_error [*64:80] ##1 rx_error) // RX error
        ))
        and
        (not Sync |=> !rx_error [*64:80] ##1 rx_error) // bad sync -> RX error
    )
    // TODO fix for stuffed bits and CRC checking
endproperty

property HoldError;
    @(posedge clk) disable iff (!n_rst)
    !rx_transfer_active |-> $stable(rx_error)
endproperty

checker USBModel();
    // done:
    assert property (TransferActive);
    /* assert property (TransferInactive); */
    assert property (HoldError);
    
    // not done:
    // TODO validate store, rx_packet, and rx_data_ready (all pretty similar, first need validation)
    
    assert property (BeginPacket);
endchecker

// DUT Port Map
usb_rx DUT (.*);

USBModel usbm();

tb_usb_transmit usb_tx = new;

assign dp = usb_tx.dp;
assign dm = usb_tx.dm;

// Test Bench Main Process
initial
begin
    // Initialize all test bench signals
    test_num = 0;
    test_case = "TB Init";

    n_rst = 1'b1;

    buffer_occupancy = 7'd0;

    expected_rx_packet = 3'd0;
    expected_rx_data_ready = 1'b0;
    expected_rx_transfer_active = 1'b0;
    expected_rx_error = 1'b0;
    expected_flush = 1'b0;
    expected_store_rx_packet_data = 1'b0;
    expected_rx_packet_data = 1'b0;

    #(0.1);

    // **************************************************
    // Test Case 1: Power-on Reset of DUT
    // **************************************************
    test_num = test_num + 1;
    test_case = "Power-on Reset of DUT";

    @(negedge clk);
    #(0.1);
    n_rst = 1'b0;

    // Check internal state was correctly reset
    #(CLK_PERIOD * 0.5);
    check_outputs("after reset applied");

    // Check internal state is maintained during a clock cycle
    #(CLK_PERIOD);
    check_outputs("after clock cycle while in reset");

    // Release reset away from a clock edge
    @(negedge clk);
    n_rst = 1'b1;
    #(CLK_PERIOD * 2);

    // Check internal state is maintained after reset released
    check_outputs("after reset was released");

    // **************************************************
    // Test Case 2:
    // **************************************************
    test_num = test_num + 1;
    test_case = "Initial Test";

    reset_dut();

    #(CLK_PERIOD * 10);

    usb_tx.enqueue_usb_token(1'b0, 7'h3a, 4'ha);
    usb_tx.send_usb_packet();

    usb_tx.enqueue_usb_token(1'b1, 7'h70, 4'h4);
    usb_tx.send_usb_packet();

    usb_tx.enqueue_usb_data(1'b0, 4, {8'h00, 8'h01, 8'h02, 8'h03});
    usb_tx.send_usb_packet();

    usb_tx.enqueue_usb_handshake(2'd0);
    usb_tx.send_usb_packet();

    usb_tx.enqueue_usb_handshake(2'd1);
    usb_tx.send_usb_packet(84ns);

    usb_tx.enqueue_usb_handshake(2'd2);
    usb_tx.send_usb_packet(82ns);

    // TODO write more test cases

end

endmodule
