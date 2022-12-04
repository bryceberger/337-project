// File name:		tb_usb_tx.sv
// Created:			12/3/2022
// Author:			Trevor Moorman
// Group number:	5
// Version:			1.0	Initial Design Entry
// Description:		Test Bench for USB TX Module of USB Full-Speed Bulk-Transfer Endpoint AHB-Lite SoC Module

`timescale 1ns/10ps

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
	wire tb_Dplus_Out, tb_Dminus_Out, tb_TX_Transfer_Active, tb_TX_Error, tb_Get_TX_Packet_Data
	
	// Test Bench Verification Signals
	integer tb_test_num;
	string tb_test_case;
	reg tb_Dplus_Out_prev, tb_Dminus_Out_prev;
	reg tb_expected_Dorig, tb_expected_TX_Transfer_Active, tb_expected_TX_Error, tb_expected_Get_TX_Packet_Data;
	
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
			$info("Test case %0d: Correct 'TX_Transfer_Active' output %s", check_tag);
		else
			$error("Test case %0d: Incorrect 'TX_Transfer_Active' output %s (Expected=0b%b, Actual=0b%b)", check_tag, tb_expected_TX_Transfer_Active, tb_TX_Transfer_Active);
		
		assert(tb_TX_Error == tb_expected_TX_Error)
			$info("Test case %0d: Correct 'TX_Error' output %s", check_tag, tb_expected_TX_Error, tb_TX_Error);
		else
			$error("Test case %0d: Incorrect 'TX_Error' output %s (Expected=0b%b, Actual=0b%b)", check_tag);
		
		assert(tb_Get_TX_Packet_Data == tb_expected_Get_TX_Packet_Data)
			$info("Test case %0d: Correct 'TX_Packet_Data' output %s", check_tag);
		else
			$error("Test case %0d: Incorrect 'TX_Packet_Data' output %s (Expected=0b%b, Actual=0b%b)", check_tag, tb_expected_Get_TX_Packet_Data, tb_Get_TX_Packet_Data);
	end
	endtask
	
	// Task to check 'sync' byte
	task check_sync;
	begin
		logic [7:0] eop_byte;
		logic [7:0] sync_byte;
		
		// Record output 'sync' byte
		integer i;
		for (i = 0; i < 8; i++) begin
			@(negedge tb_clk);
			decode_NRZI(.EOP(eop_byte[i]), .Dorig(sync_byte[i]));
			check_outputs("while outputting 'sync' byte");
		end
		
		// Check if EOP was ever asserted
		assert(eop_byte != 8'd0) $error("Test case %0d: EOP falsely set during 'sync' byte", tb_test_case_num);
		
		// Check if correct 'sync' byte outputted
		assert(sync_byte == 8'b00000001)
			$info("Test case %0d: Correct 'sync' byte outputted", tb_test_case_num);
		else
			$error("Test case %0d: Incorrect 'sync' byte outputted (Expected=0b%b, Actual=0b%b)", tb_test_case_num, 8'b00000001, sync_byte);
		
	end
	endtask
	
	// Task to check 'pid' byte
	task check_pid;
		input logic [3:0] expected_pid;
	begin
		logic [7:0] expected_pid_byte = {expected_pid[3], expected_pid[2], expected_pid[1], expected_pid[0], ~(expected_pid[3]), ~(expected_pid[2]), ~(expected_pid[1]), ~(expected_pid[0])};
		logic [7:0] eop_byte;
		logic [7:0] pid_byte;
		
		// Record output 'pid' byte
		integer i;
		for (i = 0; i < 8; i++) begin
			@(negedge tb_clk);
			decode_NRZI(.EOP(eop_byte[i]), .Dorig(pid_byte[i]));
			check_outputs("while outputting 'pid' byte");
		end
		
		// Check if EOP was ever asserted
		assert(eop_byte != 8'd0) $error("Test case %0d: EOP falsely set during 'pid' byte", tb_test_case_num);
		
		// Check if correct 'pid' byte outputted
		assert(pid_byte == expected_pid_byte)
			$info("Test case %0d: Correct 'pid' byte outputted", tb_test_case_num);
		else
			$error("Test case %0d: Incorrect 'pid' byte outputted (Expected=0b%b, Actual=0b%b)", tb_test_case_num, expected_pid_byte, pid_byte);
	end
	endtask
	
	// Task to check data
	task check_data;
		input logic [] expected_data; //TODO: Figure out how to state what the data should be as it will be a lot to manually type 64 bytes worth of data
	begin
		
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
			@(negedge tb_clk);
			decode_NRZI(.EOP(eop_bytes[i]), .Dorig(crc_bytes[i]));
			check_outputs("while outputting CRC");
		end
		
		// Check if EOP was ever asserted
		assert(eop_bytes != 16'd0) $error("Test case %0d: EOP falsely set during CRC", tb_test_case_num);
		
		// Check if correct 'pid' byte outputted
		assert(crc_bytes == expected_crc)
			$info("Test case %0d: Correct CRC outputted", tb_test_case_num);
		else
			$error("Test case %0d: Incorrect CRC outputted (Expected=0b%b, Actual=0b%b)", tb_test_case_num, expected_pid_byte, pid_byte);
	end
	endtask
	
	// Task to check 'EOP'
	task check_eop;
	begin
		logic EOP;
	
		// Check if EOP is asserted for first clock cycle
		@(negedge tb_clk);
		decode_NRZI(.EOP(EOP));
		check_outputs("while outputting EOP for first clock cycle");
		assert(EOP == 1'b1)
			$info("Test case %0d: Correct EOP asserted for first clock cycle", tb_test_case_num);
		else
			$error("Test case %0d: Incorrect EOP unasserted for first clock cycle", tb_test_case_num);
			
		// Check if EOP is asserted for second clock cycle
		@(negedge tb_clk);
		decode_NRZI(.EOP(EOP));
		check_outputs("while outputting EOP for second clock cycle");
		assert(EOP == 1'b1)
			$info("Test case %0d: Correct EOP asserted for second clock cycle", tb_test_case_num);
		else
			$error("Test case %0d: Incorrect EOP unasserted for second clock cycle", tb_test_case_num);
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
				.Get_TX_Packet_Data(tb_Get_TX_Packet_Data),
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
		tb_TX_Packet_Data = 8'd0;
		tb_Dplus_Out_prev = 1'b1;
		tb_Dminus_Out_prev = 1'b0;
		tb_expected_Dorig = 1'b1;
		tb_expected_TX_Transfer_Active = 1'b0;
		tb_expected_TX_Error = 1'b0;
		tb_expected_Get_TX_Packet_Data = 1'b0;
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
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		// Set input signals
		tb_TX_Start = 1'b1;
		tb_TX_Packet = TX_PACKET_ACK;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		// Set expected outputs given above inputs
		tb_expected_TX_Transfer_Active = 1'b1;
		tb_expected_TX_Error = 1'b0;
		tb_expected_Get_TX_Packet_Data = 1'b0;
		
		check_sync();
		check_pid(ACK_PID);
		check_eop();
		
		// **************************************************
		// Test Case 3: Nominal Packet Transmission - NAK
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - NAK";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		check_sync();
		check_pid(NAK_PID);
		check_eop();
		
		// **************************************************
		// Test Case 4: Nominal Packet Transmission - DATA0 (0 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - DATA0 (0 bytes of data)";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		//TODO
		
		// **************************************************
		// Test Case 5: Nominal Packet Transmission - DATA0 (1 byte of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - DATA0 (1 byte of data)";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		//TODO
		
		// **************************************************
		// Test Case 6: Nominal Packet Transmission - DATA0 (32 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - DATA0 (32 bytes of data)";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		//TODO
		
		// **************************************************
		// Test Case 7: Nominal Packet Transmission - DATA0 (64 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - DATA0 (64 bytes of data)";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		//TODO
		
		// **************************************************
		// Test Case 8: Nominal Packet Transmission - STALL
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Nominal Packet Transmission - STALL";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		check_sync();
		check_pid(STALL_PID);
		check_eop();
		
		// **************************************************
		// Test Case 9: Bit-Stuffing at Beginning of DATA0 Packet
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Bit-Stuffing at Beginning of DATA0 Packet";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		//TODO
		
		// **************************************************
		// Test Case 10: Bit-Stuffing at Middle of DATA0 Packet
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Bit-Stuffing at Middle of DATA0 Packet";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		//TODO
		
		// **************************************************
		// Test Case 11: Bit-Stuffing at End of DATA0 Packet
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "Bit-Stuffing at End of DATA0 Packet";
		tb_TX_Start = 1'b0;
		tb_TX_Packet = 2'd0;
		tb_Buffer_Occupancy = 7'd0;
		tb_TX_Packet_Data = 8'd0;
		reset_dut();
		
		//TODO
		
	end
endmodule
