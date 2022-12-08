`timescale 1ns/10ps

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

// Test Bench Debug Signals
reg [7:0] current_usb_byte;

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

typedef union tagged {
    byte usb_data_byte;
    struct {
        byte eop;
        byte data;
        byte num_bits;
    } usb_data_eop;
} USB_data;

USB_data data_queue[$];

function void enqueue_usb_byte(input USB_data data);
    data_queue.push_back(data);
endfunction

function USB_data dequeue_usb_byte();
    return data_queue.pop_front();
endfunction

function void remove_usb_byte();
    data_queue = data_queue[0:$-1];
endfunction

function int usb_bytes_remaining();
    return data_queue.size();
endfunction

task send_usb_bit(input time period, input bit b, input bit eop = 1'b0);
    static int ones = 0;

    if (eop == 1'b1) begin
        dp = 1'b0;
        dm = 1'b0;
        #(period);
        return;
    end

    dp ^= ~b;
    dm = ~dp;
    #(period);

    if (b == 1'b1)
        ones++;
    else
        ones = 0;

    if (ones == 6) begin
        ones = 0;
        send_usb_bit(period, 1'b0);
    end
endtask

task send_usb_packet(input time period = (250/3) * 1ns); // validate from 82 to 84 ns
    USB_data usb_data;
    automatic bit bus_state = 1'b1;
    automatic int ones = 0;
    while (usb_bytes_remaining() > 0) begin
        usb_data = dequeue_usb_byte();
        case (usb_data) matches
            tagged usb_data_byte .b: begin
                current_usb_byte = b;
                for (int i = 0; i < 8; i++) begin
                    send_usb_bit(period, b[i]);
                end
            end
            tagged usb_data_eop '{.eop, .data, .num_bits }: begin
                for (int i = 0; i < num_bits; i++) begin
                    if (eop[i] == 1'b1)
                        send_usb_bit(period, 1'b0, 1'b1);
                    else
                        send_usb_bit(period, data[i]);
                end
                break;
            end
        endcase
    end
endtask

task enqueue_usb_packet(
    input bit [3:0] pid,
    input int n_bytes, input byte bytes[]
);
    automatic byte pid_byte = {~pid, pid};
    enqueue_usb_byte(tagged usb_data_byte (8'h80));
    enqueue_usb_byte(tagged usb_data_byte (pid_byte));
    for (int i = 0; i < n_bytes; i++)
        enqueue_usb_byte(tagged usb_data_byte (bytes[i]));
    enqueue_usb_byte(tagged usb_data_eop ('{8'h03, 8'h00, 3}));
endtask

task enqueue_usb_token(
    input bit t_type, // OUT = 0, IN = 1
    input bit [6:0] address, input bit [3:0] endpoint
);
    static byte bytes [2];

    automatic bit [3:0] pid = { t_type, 3'b001 };

    // compute CRC
    automatic bit [10:0] data = {endpoint, address};
    automatic bit [4:0] crc = 5'b11111;
    logic xr;
    for (int i = 0; i < 11; i++) begin
        xr = data[i] ^ crc[4];
        crc = {crc[3:2], crc[1] ^ xr, crc[0], xr};
    end

    // send data
    bytes = { << byte { {{<<{~crc}}, endpoint[3:1]}, {endpoint[0], address} }};
    enqueue_usb_packet(pid, 2, bytes);
endtask

task enqueue_usb_data(input bit d_type, input int n_bytes, input byte data[]);
    automatic bit [3:0] pid = { d_type, 3'b011 };

    // compute CRC
    automatic bit [15:0] crc = 16'hffff;
    logic xr;
    for (int i = 0; i < n_bytes; i++) begin
        for (int j = 0; j < 8; j++) begin
            xr = data[i][j] ^ crc[15];
            crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
        end
    end

    enqueue_usb_packet(
        pid, n_bytes + 2,
        { data, { << {~crc[15:8]} }, { << {~crc[7:0]} } }
    );
endtask

task enqueue_usb_handshake(input bit [1:0] h_type); // ACK, NAK, STALL
    automatic bit [3:0] pid = { ^h_type, h_type[1], 2'b10 };
    enqueue_usb_packet(pid, 0, {});
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

property BeginPacket;
    @(posedge clk) disable iff (!n_rst)
    (!rx_transfer_active and Low) |-> (
        (Sync ##1 ( // good sync
            (TokenPID ##1 ( // token
                (Low [*8:10] or High [*8:10]) [*16] // 16 data bits
                ##[1:4] EOP // then EOP
                // TODO assertions if this happens
            ))
            or
            (DataPID ##1 (
                (
                    (Low [*8:10] or High [*8:10]) [*8] // 8 bits
                ) [*0:64] // 0-64 bytes
                ##[1:4] EOP // then EOP
                // TODO assertions if this happens
            ))
            or
            (HandshakePID ##1 ##[0:3] EOP) // handshake; immediate EOP
        ))
        or
        (
            (Sync |=> ( // good sync
                (not (TokenPID or DataPID or HandshakePID)) // bad PID
                and
                (##[64:80] rx_error) // RX error
            ))
            and
            (not Sync |=> ##[64:80] rx_error) // bad sync -> RX error
        )
    )
endproperty

property HoldError;
    @(posedge clk) disable iff (!n_rst)
    !rx_transfer_active |=> $stable(rx_error)
endproperty

property TransferValid(bit valid);
    @(posedge clk) disable iff (!n_rst)
    rx_transfer_active && valid |=> !rx_error
endproperty

property TransferEndError(bit valid);
    @(posedge clk) disable iff (!n_rst)
    !valid |=> ##[0:3] rx_error
endproperty

checker USBModel();
    static int ones = 0;
    bit silent_bus, is_valid;

    always_ff @(posedge clk)
        ones <= $stable(dp) && $stable(dm) ? ones + 1 : 0;

    // done:
    assert property (TransferActive);
    /* assert property (TransferInactive); */
    assert property (HoldError);
    
    // not done:
    assert property (TransferValid(is_valid));
    assert property (TransferEndError(is_valid));
    // TODO add to is_valid: invalid sync, bad PID, bad CRC, and bad EOP (sequential!)
    // TODO validate store, rx_packet, and rx_data_ready (all pretty similar, first need validation)
    
    assert property (BeginPacket);

    always_comb begin
        silent_bus = ones >= 55;
        /* is_valid = rx_transfer_active && silent_bus; */
        is_valid = 1'b1;
    end
endchecker

// DUT Port Map
usb_rx DUT (.*);

USBModel usbm();

// Test Bench Main Process
initial
begin
    // Initialize all test bench signals
    test_num = 0;
    test_case = "TB Init";

    n_rst = 1'b1;

    dp = 1'b1;
    dm = 1'b0;
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

    enqueue_usb_token(1'b0, 7'h3a, 4'ha);
    send_usb_packet();

    enqueue_usb_data(1'b0, 4, {8'h00, 8'h01, 8'h02, 8'h03});
    send_usb_packet();

    enqueue_usb_handshake(2'd2);
    send_usb_packet();

    enqueue_usb_handshake(2'd2);
    send_usb_packet(84ns);

    enqueue_usb_handshake(2'd2);
    send_usb_packet(82ns);

    // TODO write more test cases

end

endmodule
