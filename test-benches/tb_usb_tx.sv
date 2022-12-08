`default_nettype none
// File name:		tb_usb_tx.sv
// Created:			12/3/2022
// Author:			Trevor Moorman
// Group number:	5
// Version:			1.0	Initial Design Entry
// Description:		Test Bench for USB TX Module of USB Full-Speed Bulk-Transfer Endpoint AHB-Lite SoC Module

`timescale 1ns / 10ps

class data_gen;
    rand bit [7:0] data;

    constraint anti_stuff {
        data[1] == 1'b0;
        data[6] == 1'b0;
    }
endclass

module tb_usb_tx ();

    // Local Constants
    localparam time CHECK_DELAY = 1ns;
    localparam time CLK_PERIOD = 10ns;

    localparam bit VERBOSE = 0;

    localparam bit [1:0] 
        TX_PACKET_DATA0 = 2'd0,
        TX_PACKET_ACK = 2'd1,
        TX_PACKET_NAK = 2'd2,
        TX_PACKET_STALL = 2'd3;

    localparam bit [3:0]
	DATA0_PID = 4'b0011,
	ACK_PID = 4'b0010,
	NAK_PID = 4'b1010,
	STALL_PID = 4'b1110;

    // Test Bench DUT Port Signals
    reg clk, n_rst, tx_start;
    reg [1:0] tx_packet;
    reg [6:0] buffer_occupancy;
    reg [7:0] tx_packet_data;
    wire dp, dm, tx_transfer_active, tx_error, get_tx_packet_data;

    // Test Bench Verification Signals
    integer tb_test_num;
    string  tb_test_case;
    reg dp_prev, dm_prev;
    reg
        tb_expected_Dorig,
        tb_expected_trans_act,
        tb_expected_TX_Error,
        tb_expected_Get_TX_Packet_Data;
    bit [7:0] tb_data[];
    bit [15:0] crc;
    logic xr;
    int count;
    logic check;

    data_gen rng = new;

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

        // Wait 2 clock cycles
        @(posedge clk);
        @(posedge clk);
    endtask

    // Helper Task for Decoding Dplus_Out & Dminus_Out
    // Note: Dorig means nothing if EOP is asserted
    task decode_NRZI(output logic EOP, Dorig);
        EOP     = dp == dm;
        Dorig   = dp == dp_prev && dm == dm_prev;

        dp_prev = dp;
        dm_prev = dm;
        count++;
        check = 1;
        #(0.1);
        check = 0;
    endtask

    // Task for checking USB-TX's direct outputs
    task check_outputs(input string check_tag);
        assert (tx_transfer_active == tb_expected_trans_act)
            $info(
                "Test case %0d: Correct 'TX_Transfer_Active' output %s",
                tb_test_num,
                check_tag
            );
        else
            $error(
                "Test case %0d: Incorrect 'TX_Transfer_Active' output %s (Expected=0b%b, Actual=0b%b)",
                tb_test_num,
                check_tag,
                tb_expected_trans_act,
                tx_transfer_active
            );

        assert (tx_error == tb_expected_TX_Error)
            $info(
                "Test case %0d: Correct 'TX_Error' output %s",
                tb_test_num,
                check_tag
            );
        else
            $error(
                "Test case %0d: Incorrect 'TX_Error' output %s (Expected=0b%b, Actual=0b%b)",
                tb_test_num,
                check_tag,
                tb_expected_TX_Error,
                tx_error
            );

        assert (get_tx_packet_data == tb_expected_Get_TX_Packet_Data)
            $info(
                "Test case %0d: Correct 'GET_TX_Packet_Data' output %s",
                tb_test_num,
                check_tag
            );
        else
            $error(
                "Test case %0d: Incorrect 'GET_TX_Packet_Data' output %s (Expected=0b%b, Actual=0b%b)",
                tb_test_num,
                check_tag,
                tb_expected_Get_TX_Packet_Data,
                get_tx_packet_data
            );
    endtask

    // Task to check 'sync' byte
    task check_sync();
        logic [7:0] eop_byte;
        logic [7:0] sync_byte;

        // Record output 'sync' byte
        for (int i = 0; i < 8; i++) begin
            if (i != 0) for (int j = 0; j < 8; j++) @(negedge clk);
            decode_NRZI(.EOP(eop_byte[i]), .Dorig(sync_byte[i]));
            check_outputs("while outputting 'sync' byte");
        end

        // Check if EOP was ever asserted
        assert (eop_byte == 8'd0)
        else
            $error(
                "Test case %0d: EOP falsely set during 'sync' byte", tb_test_num
            );

        // Check if correct 'sync' byte output
        assert (sync_byte == 8'h80)
            $info("Test case %0d: Correct 'sync' byte output", tb_test_num);
        else
            $error(
                "Test case %0d: Incorrect 'sync' byte output (Expected=0b%b, Actual=0b%b)",
                tb_test_num,
                8'h80,
                sync_byte
            );

    endtask

    // Task to check 'pid' byte
    task check_pid(input logic [3:0] expected_pid);
        automatic logic [7:0] expected_pid_byte = {~expected_pid, expected_pid};
        logic [7:0] eop_byte;
        logic [7:0] pid_byte;

        // Record output 'pid' byte
        for (int i = 0; i < 8; i++) begin
            for (int j = 0; j < 8; j++) @(negedge clk);
            decode_NRZI(.EOP(eop_byte[i]), .Dorig(pid_byte[i]));
            check_outputs("while outputting 'pid' byte");
        end

        // Check if EOP was ever asserted
        assert (eop_byte == 8'd0)
        else
            $error(
                "Test case %0d: EOP falsely set during 'pid' byte", tb_test_num
            );

        // Check if correct 'pid' byte output
        assert (pid_byte == expected_pid_byte)
            $info("Test case %0d: Correct 'pid' byte output", tb_test_num);
        else
            $error(
                "Test case %0d: Incorrect 'pid' byte output (Expected=0b%b, Actual=0b%b)",
                tb_test_num,
                expected_pid_byte,
                pid_byte
            );
    endtask

    // Task to check data
    task check_data(input logic [7:0] expected_data_byte);
        logic [7:0] eop_byte;
        logic [7:0] data_byte;

        // Record output 'data' byte
        for (int i = 0; i < 8; i++) begin
            for (int j = 0; j < 8; j++) @(negedge clk);
            decode_NRZI(.EOP(eop_byte[i]), .Dorig(data_byte[i]));
            if ((i == 7) && (buffer_occupancy != 7'd0)) tb_expected_Get_TX_Packet_Data = 1;
            check_outputs("while outputting 'data' byte");
        end
        tb_expected_Get_TX_Packet_Data = 0;
        if (buffer_occupancy != 7'd0) buffer_occupancy = buffer_occupancy - 1;

        // Check if EOP was ever asserted
        assert (eop_byte == 8'd0)
        else
            $error(
                "Test case %0d: EOP falsely set during 'pid' byte", tb_test_num
            );

        // Check if correct 'data' byte output
        assert (data_byte == expected_data_byte)
            $info("Test case %0d: Correct 'data' byte output", tb_test_num);
        else
            $error(
                "Test case %0d: Incorrect 'data' byte output (Expected=0b%b, Actual=0b%b)",
                tb_test_num,
                expected_data_byte,
                data_byte
            );
    endtask

    // Task to check CRC
    task check_crc(input logic [15:0] expected_crc);
        logic [15:0] eop_bytes;
        logic [15:0] crc_bytes;

        // Record output 'pid' byte
        for (int i = 0; i < 16; i++) begin
            for (int j = 0; j < 8; j++) @(negedge clk);
            decode_NRZI(.EOP(eop_bytes[i]), .Dorig(crc_bytes[i]));
            check_outputs("while outputting CRC");
        end

        // Check if EOP was ever asserted
        assert (eop_bytes == 16'd0)
        else $error("Test case %0d: EOP falsely set during CRC", tb_test_num);

        // Check if correct 'pid' byte output
        assert (crc_bytes == expected_crc)
            $info("Test case %0d: Correct CRC output", tb_test_num);
        else
            $error(
                "Test case %0d: Incorrect CRC output (Expected=0b%b, Actual=0b%b)",
                tb_test_num,
                expected_crc,
                crc_bytes
            );
    endtask

    // Task to check 'EOP'
    task check_eop();
        logic EOP;
        logic Dorig;

        // Check if EOP is asserted for first clock cycle
        for (int j = 0; j < 8; j++) @(negedge clk);
        decode_NRZI(.EOP(EOP), .Dorig(Dorig));
        check_outputs("while outputting EOP for first clock cycle");
        assert (EOP == 1'b1)
            $info(
                "Test case %0d: Correct EOP asserted for first clock cycle",
                tb_test_num
            );
        else
            $error(
                "Test case %0d: Incorrect EOP unasserted for first clock cycle",
                tb_test_num
            );

        // Check if EOP is asserted for second clock cycle
        for (int j = 0; j < 8; j++) @(negedge clk);
        decode_NRZI(.EOP(EOP), .Dorig(Dorig));
        check_outputs("while outputting EOP for second clock cycle");
        assert (EOP == 1'b1)
            $info(
                "Test case %0d: Correct EOP asserted for second clock cycle",
                tb_test_num
            );
        else
            $error(
                "Test case %0d: Incorrect EOP unasserted for second clock cycle",
                tb_test_num
            );
    endtask

    // Task to manually check output bit-stuff
    task check_bit;
        input logic expected_bit;
        begin
            logic EOP;
            logic Dorig;

            @(negedge clk);
            decode_NRZI(.EOP(EOP), .Dorig(Dorig));

            assert (EOP == 1'b0)
                $info("Test case %0d: Correct EOP not asserted", tb_test_num);
            else $error("Test case %0d: Incorrect EOP asserted", tb_test_num);

            assert (Dorig == expected_bit)
                $info("Test case %0d: Correct bit output", tb_test_num);
            else $error("Test case %0d: Incorrect bit output", tb_test_num);

            for (int j = 0; j < 7; j++) @(negedge clk);
        end
    endtask

    // Clock Gen Block
    always begin : CLK_GEN
        clk = 1'b0;
        #(CLK_PERIOD / 2.0);
        clk = 1'b1;
        #(CLK_PERIOD / 2.0);
    end

    // DUT Port Map
    usb_tx DUT (.*);

    always @(tb_test_num) count = 0;

    // Test Bench Main Process
    initial begin
        if (!VERBOSE) $assertpassoff();
        // Initialize all test bench signals
        tb_test_num                    = 0;
        tb_test_case                   = "TB Init";
        n_rst                          = 1'b1;
        tx_start                       = 1'b0;
        tx_packet                      = 2'd0;
        buffer_occupancy               = 7'd0;
        tb_data                        = new[1];
        tb_data[0]                     = 8'd0;
        dp_prev                        = 1'b1;
        dm_prev                        = 1'b0;
        tb_expected_Dorig              = 1'b1;
        tb_expected_trans_act          = 1'b0;
        tb_expected_TX_Error           = 1'b0;
        tb_expected_Get_TX_Packet_Data = 1'b0;
        crc                            = 16'hffff;
        check                          = 0;
        count                          = 0;
        #(0.1);

        // **************************************************
        // Test Case 1: Power-on Reset of DUT
        // **************************************************
        tb_test_num  = tb_test_num + 1;
        tb_test_case = "Power-on Reset of DUT";

        // Apply reset by deasserting n_rst
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
        #(0.1);

        // Check internal state is maintained after reset released
        check_outputs("after reset was released");

        // **************************************************
        // Test Case 2: Nominal Packet Transmission - ACK
        // **************************************************
        tb_test_num      = tb_test_num + 1;
        tb_test_case     = "Nominal Packet Transmission - ACK";
        tx_start         = 1'b0;
        tx_packet        = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data          = new[1];
        reset_dut();

        // Set input signals
        tx_start              = 1'b1;
        tx_packet             = TX_PACKET_ACK;
        buffer_occupancy      = 7'd0;
        tb_data[0]            = 8'd0;
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(ACK_PID);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs("after transmitting ACK packet");

        @(posedge clk);

        // **************************************************
        // Test Case 3: Nominal Packet Transmission - NAK
        // **************************************************
        tb_test_num      = tb_test_num + 1;
        tb_test_case     = "Nominal Packet Transmission - NAK";
        tx_start         = 1'b0;
        tx_packet        = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data          = new[1];
        reset_dut();

        // Set input signals
        tx_start              = 1'b1;
        tx_packet             = TX_PACKET_NAK;
        buffer_occupancy      = 7'd0;
        tb_data[0]            = 8'd0;
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(NAK_PID);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs("after transmitting NAK packet");

        @(posedge clk);

        // **************************************************
        // Test Case 4: Nominal Packet Transmission - DATA0 (0 bytes of data)
        // **************************************************
        tb_test_num = tb_test_num + 1;
        tb_test_case = "Nominal Packet Transmission - DATA0 (0 bytes of data)";
        tx_start = 1'b0;
        tx_packet = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data = new[1];
        reset_dut();

        // Set input signals
        tx_start              = 1'b1;
        tx_packet             = TX_PACKET_DATA0;
        buffer_occupancy      = 7'd0;
        tb_data[0]            = 8'd0;
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;
        crc                   = 16'hffff;

        for (int i = 0; i < 4; i++) @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(DATA0_PID);
        check_crc(~crc);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs("after transmitting DATA0 packet w/ 0 bytes of data");
        
        @(posedge clk);

        // **************************************************
        // Test Case 5: Nominal Packet Transmission - DATA0 (1 byte of data)
        // **************************************************
        tb_test_num = tb_test_num + 1;
        tb_test_case = "Nominal Packet Transmission - DATA0 (1 byte of data)";
        tx_start = 1'b0;
        tx_packet = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data = new[1];
        reset_dut();

        // Set input signals
        tx_start         = 1'b1;
        tx_packet        = TX_PACKET_DATA0;
        buffer_occupancy = 7'd0;
        assert (rng.randomize() == 1);
        tb_data[0]            = rng.data;
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;
        crc                   = 16'hffff;
        for (int i = 0; i < 1; i++) begin
            for (int j = 0; j < 8; j++) begin
                xr  = tb_data[i][j] ^ crc[15];
                crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
            end
        end

        for (int i = 0; i < 4; i++) @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(DATA0_PID);
        check_data(tb_data[0]);
        check_crc(~crc);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs("after transmitting DATA0 packet w/ 1 byte of data");
        
        @(posedge clk);

        // **************************************************
        // Test Case 6: Nominal Packet Transmission - DATA0 (32 bytes of data)
        // **************************************************
        tb_test_num = tb_test_num + 1;
        tb_test_case = "Nominal Packet Transmission - DATA0 (32 bytes of data)";
        tx_start = 1'b0;
        tx_packet = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data = new[1];
        reset_dut();

        // Set input signals
        tx_start         = 1'b1;
        tx_packet        = TX_PACKET_DATA0;
        buffer_occupancy = 7'd31;
        assert (rng.randomize() == 1);
        for (int i = 0; i < 32; i++) begin
            assert (rng.randomize() == 1);
            tb_data[i] = rng.data;
        end
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;
        crc                   = 16'hffff;
        for (int i = 0; i < 32; i++) begin
            for (int j = 0; j < 8; j++) begin
                xr  = tb_data[i][j] ^ crc[15];
                crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
            end
        end

        for (int i = 0; i < 4; i++) @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(DATA0_PID);
        for (int i = 0; i < 32; i++) begin
            tx_packet_data = tb_data[i];
            check_data(tb_data[i]);
        end
        check_crc(~crc);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs("after transmitting DATA0 packet w/ 32 bytes of data");
        
        @(posedge clk);

        // **************************************************
        // Test Case 7: Nominal Packet Transmission - DATA0 (64 bytes of data)
        // **************************************************
        tb_test_num = tb_test_num + 1;
        tb_test_case = "Nominal Packet Transmission - DATA0 (64 bytes of data)";
        tx_start = 1'b0;
        tx_packet = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data = new[1];
        reset_dut();

        // Set input signals
        tx_start         = 1'b1;
        tx_packet        = TX_PACKET_DATA0;
        buffer_occupancy = 7'd63;
        assert (rng.randomize() == 1);
        for (int i = 0; i < 64; i++) begin
            assert (rng.randomize() == 1);
            tb_data[i] = rng.data;
        end
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;
        crc                   = 16'hffff;
        for (int i = 0; i < 64; i++) begin
            for (int j = 0; j < 8; j++) begin
                xr  = tb_data[i][j] ^ crc[15];
                crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
            end
        end

        for (int i = 0; i < 4; i++) @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(DATA0_PID);
        for (int i = 0; i < 64; i++) begin
            tx_packet_data = tb_data[i];
            check_data(tb_data[i]);
        end
        check_crc(~crc);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs("after transmitting DATA0 packet w/ 64 bytes of data");
        
        @(posedge clk);

        // **************************************************
        // Test Case 8: Nominal Packet Transmission - STALL
        // **************************************************
        tb_test_num      = tb_test_num + 1;
        tb_test_case     = "Nominal Packet Transmission - STALL";
        tx_start         = 1'b0;
        tx_packet        = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data          = new[1];
        reset_dut();

        // Set input signals
        tx_start              = 1'b1;
        tx_packet             = TX_PACKET_STALL;
        buffer_occupancy      = 7'd0;
        tb_data[0]            = 8'd0;
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;

        for (int i = 0; i < 4; i++) @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(STALL_PID);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs("after transmitting STALL packet");

        // **************************************************
        // Test Case 9: Bit-Stuffing at Beginning of DATA0 Packet
        // **************************************************
        tb_test_num      = tb_test_num + 1;
        tb_test_case     = "Bit-Stuffing at Beginning of DATA0 Packet";
        tx_start         = 1'b0;
        tx_packet        = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data          = new[1];
        reset_dut();

        // Set input signals
        tx_start              = 1'b1;
        tx_packet             = TX_PACKET_DATA0;
        buffer_occupancy      = 7'd0;
        tb_data[0]            = 8'b11111111;
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;
        crc                   = 16'hffff;
        for (int i = 0; i < 1; i++) begin
            for (int j = 0; j < 8; j++) begin
                xr  = tb_data[i][j] ^ crc[15];
                crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
            end
        end

        for (int i = 0; i < 4; i++) @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(DATA0_PID);

        // Manually check data output
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b0);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);

        check_crc(~crc);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs(
            "after transmitting DATA0 packet w/ bit-stuffing at beginning");
            
        @(posedge clk);

        // **************************************************
        // Test Case 10: Bit-Stuffing at Middle of DATA0 Packet
        // **************************************************
        tb_test_num      = tb_test_num + 1;
        tb_test_case     = "Bit-Stuffing at Middle of DATA0 Packet";
        tx_start         = 1'b0;
        tx_packet        = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data          = new[1];
        reset_dut();

        // Set input signals
        tx_start              = 1'b1;
        tx_packet             = TX_PACKET_DATA0;
        buffer_occupancy      = 7'd0;
        tb_data[0]            = 8'b01111110;
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;
        crc                   = 16'hffff;
        for (int i = 0; i < 1; i++) begin
            for (int j = 0; j < 8; j++) begin
                xr  = tb_data[i][j] ^ crc[15];
                crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
            end
        end

        for (int i = 0; i < 4; i++) @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(DATA0_PID);

        // Manually check data output
        check_bit(1'b0);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b0);
        check_bit(1'b0);

        check_crc(~crc);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs(
            "after transmitting DATA0 packet w/ bit-stuffing at middle");
            
        @(posedge clk);

        // **************************************************
        // Test Case 11: Bit-Stuffing at End of DATA0 Packet
        // **************************************************
        tb_test_num      = tb_test_num + 1;
        tb_test_case     = "Bit-Stuffing at End of DATA0 Packet";
        tx_start         = 1'b0;
        tx_packet        = 2'd0;
        buffer_occupancy = 7'd0;
        tb_data          = new[1];
        reset_dut();

        // Set input signals
        tx_start              = 1'b1;
        tx_packet             = TX_PACKET_DATA0;
        buffer_occupancy      = 7'd0;
        tb_data[0]            = 8'b00111111;
        tx_packet_data        = tb_data[0];

        // Check outputs
        tb_expected_trans_act = 1'b1;
        crc                   = 16'hffff;
        for (int i = 0; i < 1; i++) begin
            for (int j = 0; j < 8; j++) begin
                xr  = tb_data[i][j] ^ crc[15];
                crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
            end
        end

        for (int i = 0; i < 4; i++) @(posedge clk);
        check_sync();
        tx_start = 1'b0;
        check_pid(DATA0_PID);

        // Manually check data output
        check_bit(1'b0);
        check_bit(1'b0);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b1);
        check_bit(1'b0);

        check_crc(~crc);
        check_eop();

        for (int i = 0; i < 12; i++) @(posedge clk);
        tb_expected_trans_act = 1'b0;
        check_outputs("after transmitting DATA0 packet w/ bit-stuffing at end");
    end
endmodule
