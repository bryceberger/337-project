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
reg tb_clk, tb_n_rst;
reg tb_dp, tb_dm;
wire [2:0] tb_rx_packet;
wire tb_rx_data_ready, tb_rx_transfer_active, tb_rx_error;
wire tb_flush, tb_store_rx_packet_data;
wire [7:0] tb_rx_packet_data;
reg [6:0] tb_buffer_occupancy;

// Test Bench Expected Signals
reg [2:0] tb_expected_rx_packet;
reg tb_expected_rx_data_ready;
reg tb_expected_rx_transfer_active;
reg tb_expected_rx_error;
reg tb_expected_flush;
reg tb_expected_store_rx_packet_data;
reg [7:0] tb_expected_rx_packet_data;

// Test Bench Debug Signals
reg [7:0] tb_current_usb_byte;
reg tb_stuff_bit;
reg [15:0] tb_packet;
reg [4:0] tb_crc;
reg [10:0] tb_data;

// Test Bench Verification Signals
integer tb_test_num;
string tb_test_case;

// Task for Resetting DUT
task reset_dut();
    // Activate reset signal
    tb_n_rst = 1'b0;

    // Wait 2 clock cycles
    @(posedge tb_clk);
    @(posedge tb_clk);

    // Release reset signal away from clock's posedge
    @(negedge tb_clk);
    tb_n_rst = 1'b1;

    // Wait
    @(negedge tb_clk);
endtask

`define info(mesg) $info("Test case %02d: %s", tb_test_num, mesg)
`define error(mesg, got, exp) $error( \
        "Test case %02d: %s (got %d, expected %d)", \
        tb_test_num, mesg, got, exp \
    )

task check_outputs(string check);
    /* reg [2:0] tb_rx_packet; */
    assert(tb_rx_packet == tb_expected_rx_packet)
        `info("correct rx_packet");
    else
        `error("incorrect rx_packet", tb_rx_packet, tb_expected_rx_packet);
    /* reg tb_rx_data_ready; */
    assert(tb_rx_data_ready == tb_expected_rx_data_ready)
        `info("correct rx_data_ready");
    else
        `error("rx_data_ready", tb_rx_data_ready, tb_expected_rx_data_ready);
    /* reg tb_rx_transfer_active */
    assert(tb_rx_transfer_active == tb_expected_rx_transfer_active)
        `info("correct rx_transfer_active");
    else
        `error(
            "rx_transfer_active",
            tb_rx_transfer_active, tb_expected_rx_transfer_active
        );
    /* reg tb_rx_error; */
    assert(tb_rx_error == tb_expected_rx_error)
        `info("correct rx_error");
    else
        `error("rx_error", tb_rx_error, tb_expected_rx_error);
    /* reg tb_flush; */
    assert(tb_flush == tb_expected_flush)
        `info("correct flush");
    else
        `error("flush", tb_flush, tb_expected_flush);
    /* reg tb_store_rx_packet_data; */
    assert(tb_store_rx_packet_data == tb_expected_store_rx_packet_data)
        `info("correct store_rx_packet_data");
    else
        `error(
            "store_rx_packet_data",
            tb_store_rx_packet_data, tb_expected_store_rx_packet_data
        );
    /* reg [7:0] tb_rx_packet_data; */
    assert(tb_rx_packet_data == tb_expected_rx_packet_data)
        `info("correct rx_packet_data");
    else
        `error("rx_packet_data", tb_rx_packet_data, tb_expected_rx_packet_data);
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
        tb_dp = 1'b0;
        tb_dm = 1'b0;
        #(period);
        return;
    end

    tb_dp ^= ~b;
    tb_dm = ~tb_dp;
    #(period);

    if (b == 1'b1)
        ones++;
    else
        ones = 0;

    if (ones == 6) begin
        ones = 0;
        tb_stuff_bit = 1'b1;
        send_usb_bit(period, 1'b0);
        tb_stuff_bit = 1'b0;
    end
endtask

task send_usb_packet(input time period = (250/3) * 1ns);
    USB_data usb_data;
    automatic bit bus_state = 1'b1;
    automatic int ones = 0;
    while (usb_bytes_remaining() > 0) begin
        usb_data = dequeue_usb_byte();
        case (usb_data) matches
            tagged usb_data_byte .b: begin
                tb_current_usb_byte = b;
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
    $info("num: %d", n_bytes);
    for (int i = 0; i < n_bytes; i++) begin
        $info("b: %02x", bytes[i]);
        enqueue_usb_byte(tagged usb_data_byte (bytes[i]));
    end
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
    tb_data = data;
    for (int i = 0; i < 11; i++) begin
        xr = data[i] ^ crc[4];
        crc = {crc[3:2], crc[1] ^ xr, crc[0], xr};
    end

    // send data
    tb_crc = crc;
    bytes = { << byte { {{<<{~crc}}, endpoint[3:1]}, {endpoint[0], address} }};
    tb_packet = {bytes[1], bytes[0]};
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

    // byte data [0:3];
    /* enqueue_usb_packet(pid, n_bytes + 2, {crc[15:8], crc[7:0], { << byte {data} }}); */
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
    tb_clk = 1'b0;
    #(CLK_PERIOD / 2.0);
    tb_clk = 1'b1;
    #(CLK_PERIOD / 2.0);
end

// DUT Port Map
usb_rx DUT (
    .clk(tb_clk), .n_rst(tb_n_rst),
    // USB input lines
    .dp(tb_dp), .dm(tb_dm),
    // Outputs to AHB-lite interface
    .rx_packet(tb_rx_packet),
    .rx_data_ready(tb_rx_data_ready),
    .rx_transfer_active(tb_rx_transfer_active),
    .rx_error(tb_rx_error),
    // I/O from FIFO
    .flush(tb_flush), .store_rx_packet_data(tb_store_rx_packet_data),
    .rx_packet_data(tb_rx_packet_data),
    .buffer_occupancy(tb_buffer_occupancy)
);

// Test Bench Main Process
initial
begin
    // Initialize all test bench signals
    tb_test_num = 0;
    tb_test_case = "TB Init";

    tb_n_rst = 1'b1;

    tb_dp = 1'b1;
    tb_dm = 1'b0;
    tb_buffer_occupancy = 7'd0;

    tb_expected_rx_packet = 3'd0;
    tb_expected_rx_data_ready = 1'b0;
    tb_expected_rx_transfer_active = 1'b0;
    tb_expected_rx_error = 1'b0;
    tb_expected_flush = 1'b0;
    tb_expected_store_rx_packet_data = 1'b0;
    tb_expected_rx_packet_data = 1'b0;

    #(0.1);

    // **************************************************
    // Test Case 1: Power-on Reset of DUT
    // **************************************************
    tb_test_num = tb_test_num + 1;
    tb_test_case = "Power-on Reset of DUT";

    @(negedge tb_clk);
    #(0.1);
    tb_n_rst = 1'b0;

    // Check internal state was correctly reset
    #(CLK_PERIOD * 0.5);
    check_outputs("after reset applied");

    // Check internal state is maintained during a clock cycle
    #(CLK_PERIOD);
    check_outputs("after clock cycle while in reset");

    // Release reset away from a clock edge
    @(negedge tb_clk);
    tb_n_rst = 1'b1;
    #(CLK_PERIOD * 2);

    // Check internal state is maintained after reset released
    check_outputs("after reset was released");

    // **************************************************
    // Test Case 2: Power-on Reset of DUT
    // **************************************************
    tb_test_num = tb_test_num + 1;
    tb_test_case = "Power-on Reset of DUT";

    reset_dut();

    enqueue_usb_token(1'b0, 7'h3a, 4'ha);
    send_usb_packet();

    enqueue_usb_data(1'b0, 4, {8'h00, 8'h01, 8'h02, 8'h03});
    send_usb_packet();

    enqueue_usb_handshake(2'd0);
    send_usb_packet();

end

endmodule
