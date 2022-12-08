// File name:		tb_usb_tx.sv
// Created:			12/3/2022
// Author:			Trevor Moorman
// Group number:	5
// Version:			1.0	Initial Design Entry
// Description:		Test Bench for USB TX Module of USB Full-Speed Bulk-Transfer Endpoint AHB-Lite SoC Module

`timescale 1ns/10ps

class data_gen;
	rand bit [7:0] data;

	constraint anti_stuff {
		data[1] == 1'b0;
		data[6] == 1'b0;
	}
endclass

module tb_usb_tx();

	// Local Constants
	localparam CHECK_DELAY = 1ns;
	localparam CLK_PERIOD = 10ns;

	localparam [1:0] TX_PACKET_DATA0 = 2'd0;
	localparam [1:0] TX_PACKET_ACK = 2'd1;
	localparam [1:0] TX_PACKET_NAK = 2'd2;
	localparam [1:0] TX_PACKET_STALL = 2'd3;

	localparam [3:0] DATA0_PID = 4'b0011;
	localparam [3:0] ACK_PID = 4'b0010;
	localparam [3:0] NAK_PID = 4'b1010;
	localparam [3:0] STALL_PID = 4'b1110;

	// Test Bench DUT Port Signals
	reg tb_clk, tb_n_rst, tb_TX_Start;
	reg [1:0] tb_TX_Packet;
	reg [6:0] tb_Buffer_Occupancy;
	reg [7:0] tb_TX_Packet_Data;
	wire tb_Dplus_Out, tb_Dminus_Out, tb_TX_Transfer_Active, tb_TX_Error, tb_Get_TX_Packet_Data;

	// Test Bench Verification Signals
	integer tb_test_num;
	string tb_test_case;
	reg tb_Dplus_Out_prev, tb_Dminus_Out_prev;
	reg tb_expected_Dorig, tb_expected_TX_Transfer_Active, tb_expected_TX_Error, tb_expected_Get_TX_Packet_Data;
  reg [7:0] tb_Packet_Data [];
	bit [15:0] crc;
	logic xr;

	data_gen rng = new;

	// Task for Resetting DUT
	task reset_dut;
	begin
		// Activate reset signal
		tb_n_rst = 1'b0;

		// Wait 2 clock cycles
		@(posedge tb_clk);
		@(posedge tb_clk);

		// Release reset signal away from clock's posedge
		@(negedge tb_clk);
		tb_n_rst = 1'b1;

		// Wait 2 clock cycles
		@(posedge tb_clk);
		@(posedge tb_clk);
	end
	endtask

	// Helper Task for Decoding Dplus_Out & Dminus_Out
	task decode_NRZI;
		output logic EOP;
		output logic Dorig; // Note: Dorig means nothing if EOP is asserted
	begin
		EOP = ((tb_Dplus_Out == 1'b1) && (tb_Dminus_Out == 1'b1)) ? 1'b1 : 1'b0;
		Dorig = ((tb_Dplus_Out == tb_Dplus_Out_prev) && (tb_Dminus_Out == tb_Dminus_Out_prev)) ? 1'b1 : 1'b0;

		tb_Dplus_Out_prev = tb_Dplus_Out;
		tb_Dminus_Out_prev = tb_Dminus_Out;
	end
	endtask

	// Task for checking USB-TX's direct outputs
	task check_outputs;
		input string check_tag;
	begin
		assert(tb_TX_Transfer_Active == tb_expected_TX_Transfer_Active)
			$info("Test case %0d: Correct 'TX_Transfer_Active' output %s", tb_test_num, check_tag);
		else
			$error("Test case %0d: Incorrect 'TX_Transfer_Active' output %s (Expected=0b%b, Actual=0b%b)", tb_test_num, check_tag, tb_expected_TX_Transfer_Active, tb_TX_Transfer_Active);

		assert(tb_TX_Error == tb_expected_TX_Error)
			$info("Test case %0d: Correct 'TX_Error' output %s", tb_test_num, check_tag);
		else
			$error("Test case %0d: Incorrect 'TX_Error' output %s (Expected=0b%b, Actual=0b%b)", tb_test_num, check_tag, tb_expected_TX_Error, tb_TX_Error);

		assert(tb_Get_TX_Packet_Data == tb_expected_Get_TX_Packet_Data)
			$info("Test case %0d: Correct 'TX_Packet_Data' output %s", tb_test_num, check_tag);
		else
			$error("Test case %0d: Incorrect 'TX_Packet_Data' output %s (Expected=0b%b, Actual=0b%b)", tb_test_num, check_tag, tb_expected_Get_TX_Packet_Data, tb_Get_TX_Packet_Data);
	end
	endtask

	// Task to check 'sync' byte
	task check_sync;
	begin
		logic [7:0] eop_byte;
		logic [7:0] sync_byte;

		// Record output 'sync' byte
		for (int i = 0; i < 8; i++) begin
			if (i != 0) for(int j = 0; j < 8; j++) @(negedge tb_clk);
			decode_NRZI(.EOP(eop_byte[i]), .Dorig(sync_byte[i]));
			check_outputs("while outputting 'sync' byte");
		end

		// Check if EOP was ever asserted
		assert(eop_byte != 8'd0) $error("Test case %0d: EOP falsely set during 'sync' byte", tb_test_num);

		// Check if correct 'sync' byte outputted
		assert(sync_byte == 8'b00000001)
			$info("Test case %0d: Correct 'sync' byte outputted", tb_test_num);
		else
			$error("Test case %0d: Incorrect 'sync' byte outputted (Expected=0b%b, Actual=0b%b)", tb_test_num, 8'b00000001, sync_byte);

	end
	endtask

	// Task to check 'pid' byte
	task check_pid;
		input logic [3:0] expected_pid;
	begin
		automatic logic [7:0] expected_pid_byte = {expected_pid[3], expected_pid[2], expected_pid[1], expected_pid[0], ~(expected_pid[3]), ~(expected_pid[2]), ~(expected_pid[1]), ~(expected_pid[0])};
		logic [7:0] eop_byte;
		logic [7:0] pid_byte;

		// Record output 'pid' byte
		integer i;
		for (i = 0; i < 8; i++) begin
			if (i != 0) for(int j = 0; j < 8; j++) @(negedge tb_clk);
			decode_NRZI(.EOP(eop_byte[i]), .Dorig(pid_byte[i]));
			check_outputs("while outputting 'pid' byte");
		end

		// Check if EOP was ever asserted
		assert(eop_byte != 8'd0) $error("Test case %0d: EOP falsely set during 'pid' byte", tb_test_num);

		// Check if correct 'pid' byte outputted
		assert(pid_byte == expected_pid_byte)
			$info("Test case %0d: Correct 'pid' byte outputted", tb_test_num);
		else
			$error("Test case %0d: Incorrect 'pid' byte outputted (Expected=0b%b, Actual=0b%b)", tb_test_num, expected_pid_byte, pid_byte);
	end
	endtask

	// Task to check data
	task check_data;
		input logic [7:0] expected_data_byte;
	begin
		logic [7:0] eop_byte;
		logic [7:0] data_byte;

		// Record output 'data' byte
		integer i;
		for (i = 0; i < 8; i++) begin
			if (i != 0) for(int j = 0; j < 8; j++) @(negedge tb_clk);
			decode_NRZI(.EOP(eop_byte[i]), .Dorig(data_byte[i]));
			if (i == 7) tb_expected_Get_TX_Packet_Data = 1;
			check_outputs("while outputting 'data' byte");
		end
		tb_expected_Get_TX_Packet_Data = 0;
		tb_Buffer_Occupancy = tb_Buffer_Occupancy - 1;

		// Check if EOP was ever asserted
		assert(eop_byte != 8'd0) $error("Test case %0d: EOP falsely set during 'pid' byte", tb_test_num);

		// Check if correct 'data' byte outputted
		assert(data_byte == expected_data_byte)
			$info("Test case %0d: Correct 'pid' byte outputted", tb_test_num);
		else
			$error("Test case %0d: Incorrect 'pid' byte outputted (Expected=0b%b, Actual=0b%b)", tb_test_num, expected_data_byte, data_byte);
	end
	endtask

	// Task to check CRC
	task check_crc;
		input logic [15:0] expected_crc;
	begin
		logic [15:0] eop_bytes;
		logic [15:0] crc_bytes;

		// Record output 'pid' byte
		integer i;
		for (i = 0; i < 16; i++) begin
			if (i != 0) for(int j = 0; j < 8; j++) @(negedge tb_clk);
			decode_NRZI(.EOP(eop_bytes[i]), .Dorig(crc_bytes[i]));
			check_outputs("while outputting CRC");
		end

		// Check if EOP was ever asserted
		assert(eop_bytes != 16'd0) $error("Test case %0d: EOP falsely set during CRC", tb_test_num);

		// Check if correct 'pid' byte outputted
		assert(crc_bytes == expected_crc)
			$info("Test case %0d: Correct CRC outputted", tb_test_num);
		else
			$error("Test case %0d: Incorrect CRC outputted (Expected=0b%b, Actual=0b%b)", tb_test_num, expected_crc, crc_bytes);
	end
	endtask

	// Task to check 'EOP'
	task check_eop;
	begin
		logic EOP;
		logic Dorig;

		// Check if EOP is asserted for first clock cycle
		for(int j = 0; j < 8; j++) @(negedge tb_clk);
		decode_NRZI(.EOP(EOP), .Dorig(Dorig));
		check_outputs("while outputting EOP for first clock cycle");
		assert(EOP == 1'b1)
			$info("Test case %0d: Correct EOP asserted for first clock cycle", tb_test_num);
		else
			$error("Test case %0d: Incorrect EOP unasserted for first clock cycle", tb_test_num);

		// Check if EOP is asserted for second clock cycle
		for(int j = 0; j < 8; j++) @(negedge tb_clk);
		decode_NRZI(.EOP(EOP), .Dorig(Dorig));
		check_outputs("while outputting EOP for second clock cycle");
		assert(EOP == 1'b1)
			$info("Test case %0d: Correct EOP asserted for second clock cycle", tb_test_num);
		else
			$error("Test case %0d: Incorrect EOP unasserted for second clock cycle", tb_test_num);
	end
	endtask

	// Task to manually check output bit-stuff
	task check_bit;
		input logic expected_bit;
	begin
		logic EOP;
		logic Dorig;

		@(negedge tb_clk);
		decode_NRZI(.EOP(EOP), .Dorig(Dorig));

		assert(EOP == 1'b0)
			$info("Test case %0d: Correct EOP not asserted", tb_test_num);
		else
			$error("Test case %0d: Incorrect EOP asserted", tb_test_num);

		assert(Dorig == expected_bit)
			$info("Test case %0d: Correct bit output", tb_test_num);
		else
			$error("Test case %0d: Incorrect bit output", tb_test_num);

		for(int j = 0; j < 7; j++) @(negedge tb_clk);
	end
	endtask

	// Clock Gen Block
	always begin: CLK_GEN
		tb_clk = 1'b0;
		#(CLK_PERIOD / 2.0);
		tb_clk = 1'b1;
		#(CLK_PERIOD / 2.0);
	end

	// DUT Port Map
	usb_tx DUT (
				.clk(tb_clk),
				.n_rst(tb_n_rst),
				.TX_Start(tb_TX_Start),
				.TX_Packet(tb_TX_Packet),
				.Buffer_Occupancy(tb_Buffer_Occupancy),
				.TX_Packet_Data(tb_TX_Packet_Data),
				.Dplus_Out(tb_Dplus_Out),
				.Dminus_Out(tb_Dminus_Out),
				.TX_Transfer_Active(tb_TX_Transfer_Active),
				.TX_Error(tb_TX_Error),
				.Get_TX_Packet_Data(tb_Get_TX_Packet_Data)
				);

	// Test Bench Main Process
	initial
	begin
		// Initialize all test bench signals
		tb_test_num = 0;
		tb_test_case = "TB Init";
		tb_n_rst = 1'b1;
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[1];
		tb_Packet_Data[0] = 8'd0;
		tb_Dplus_Out_prev = 1'b1;
		tb_Dminus_Out_prev = 1'b0;
		tb_expected_Dorig = 1'b1;
		tb_expected_TX_Transfer_Active = 1'b0;
		tb_expected_TX_Error = 1'b0;
		tb_expected_Get_TX_Packet_Data = 1'b0;
		crc = 16'hffff;
		#(0.1);

		// **************************************************
		// Test Case 1: Power-on Reset of DUT
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Power-on Reset of DUT";

		// Apply reset by deasserting tb_n_rst
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
		#(0.1);

		// Check internal state is maintained after reset released
		check_outputs("after reset was released");

		// **************************************************
		// Test Case 2: Nominal Packet Transmission - ACK
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - ACK";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[1];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_ACK;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data[0] = 8'd0;
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;

		@(posedge tb_clk);
		@(posedge tb_clk);
		@(posedge tb_clk);
		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
		check_pid(ACK_PID);
		check_eop();

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting ACK packet");

		// **************************************************
		// Test Case 3: Nominal Packet Transmission - NAK
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - NAK";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[1];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_NAK;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data[0] = 8'd0;
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;

		@(posedge tb_clk);
		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
		check_pid(NAK_PID);
		check_eop();

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting NAK packet");

		// **************************************************
		// Test Case 4: Nominal Packet Transmission - DATA0 (0 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - DATA0 (0 bytes of data)";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[1];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_DATA0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data[0] = 8'd0;
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;
		crc = 16'hffff;

		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
		check_pid(DATA0_PID);
		check_crc(~crc);
		check_eop();

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting DATA0 packet w/ 0 bytes of data");

		// **************************************************
		// Test Case 5: Nominal Packet Transmission - DATA0 (1 byte of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - DATA0 (1 byte of data)";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[1];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_DATA0;
		tb_Buffer_Occupancy = 7'd1;
		assert (rng.randomize() == 1);
		tb_Packet_Data[0] = rng.data;
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;
		crc = 16'hffff;
    for (int i = 0; i < 1; i++) begin
        for (int j = 0; j < 8; j++) begin
            xr = tb_Packet_Data[i][j] ^ crc[15];
            crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
        end
    end

		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
		check_pid(DATA0_PID);
		check_data(tb_Packet_Data[0]);
		check_crc(~crc);
		check_eop();

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting DATA0 packet w/ 1 byte of data");

		// **************************************************
		// Test Case 6: Nominal Packet Transmission - DATA0 (32 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - DATA0 (32 bytes of data)";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[32];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_DATA0;
		tb_Buffer_Occupancy = 7'd32;
		foreach (tb_Packet_Data[i]) begin
			assert (rng.randomize() == 1);
			tb_Packet_Data[i] = rng.data;
		end
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;
		crc = 16'hffff;
    for (int i = 0; i < 32; i++) begin
        for (int j = 0; j < 8; j++) begin
            xr = tb_Packet_Data[i][j] ^ crc[15];
            crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
        end
    end

		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
		check_pid(DATA0_PID);
		foreach (tb_Packet_Data[i]) begin
			tb_TX_Packet_Data = tb_Packet_Data[i];
			check_data(tb_Packet_Data[i]);
		end
		check_crc(~crc);
		check_eop();

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting DATA0 packet w/ 32 bytes of data");

		// **************************************************
		// Test Case 7: Nominal Packet Transmission - DATA0 (64 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - DATA0 (64 bytes of data)";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[64];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_DATA0;
		tb_Buffer_Occupancy = 7'd64;
		foreach (tb_Packet_Data[i]) begin
			assert (rng.randomize() == 1);
			tb_Packet_Data[i] = rng.data;
		end
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;
		crc = 16'hffff;
    for (int i = 0; i < 64; i++) begin
        for (int j = 0; j < 8; j++) begin
            xr = tb_Packet_Data[i][j] ^ crc[15];
            crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
        end
    end

		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
		check_pid(DATA0_PID);
		foreach (tb_Packet_Data[i]) begin
			tb_TX_Packet_Data = tb_Packet_Data[i];
			check_data(tb_Packet_Data[i]);
		end
		check_crc(~crc);
		check_eop();

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting DATA0 packet w/ 64 bytes of data");

		// **************************************************
		// Test Case 8: Nominal Packet Transmission - STALL
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - STALL";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[1];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_STALL;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data[0] = 8'd0;
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;

		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
		check_pid(STALL_PID);
		check_eop();

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting STALL packet");

		// **************************************************
		// Test Case 9: Bit-Stuffing at Beginning of DATA0 Packet
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Bit-Stuffing at Beginning of DATA0 Packet";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[1];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_DATA0;
		tb_Buffer_Occupancy = 7'd1;
		tb_Packet_Data[0] = 8'b11111111;
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;
		crc = 16'hffff;
    for (int i = 0; i < 1; i++) begin
        for (int j = 0; j < 8; j++) begin
            xr = tb_Packet_Data[i][j] ^ crc[15];
            crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
        end
    end

		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
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

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting DATA0 packet w/ bit-stuffing at beginning");

		// **************************************************
		// Test Case 10: Bit-Stuffing at Middle of DATA0 Packet
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Bit-Stuffing at Middle of DATA0 Packet";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[1];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_DATA0;
		tb_Buffer_Occupancy = 7'd1;
		tb_Packet_Data[0] = 8'b01111110;
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;
		crc = 16'hffff;
    for (int i = 0; i < 1; i++) begin
        for (int j = 0; j < 8; j++) begin
            xr = tb_Packet_Data[i][j] ^ crc[15];
            crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
        end
    end

		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
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

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting DATA0 packet w/ bit-stuffing at middle");

		// **************************************************
		// Test Case 11: Bit-Stuffing at End of DATA0 Packet
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Bit-Stuffing at End of DATA0 Packet";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_Packet_Data = new[1];
		reset_dut();

		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_DATA0;
		tb_Buffer_Occupancy = 7'd1;
		tb_Packet_Data[0] = 8'b00111111;
		tb_TX_Packet_Data = tb_Packet_Data[0];

		// Check outputs
		tb_expected_TX_Transfer_Active = 1'b1;
		crc = 16'hffff;
    for (int i = 0; i < 1; i++) begin
        for (int j = 0; j < 8; j++) begin
            xr = tb_Packet_Data[i][j] ^ crc[15];
            crc = {crc[14] ^ xr, crc[13:2], crc[1] ^ xr, crc[0], xr};
        end
    end

		@(posedge tb_clk);
		check_sync();
		tb_TX_Start = 1'b0;
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

		tb_expected_TX_Transfer_Active = 1'b0;
		check_outputs("after transmitting DATA0 packet w/ bit-stuffing at end");
	end
endmodule
