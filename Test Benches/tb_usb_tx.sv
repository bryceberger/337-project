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
	
	// Test Bench DUT Port Signals
	reg tb_clk, tb_n_rst;
	reg [1:0] tb_TX_Packet;
	reg [6:0] tb_Buffer_Occupancy;
	reg [7:0] tb_TX_Packet_Data;
	wire tb_Dplus_Out, tb_Dminus_Out, tb_TX_Transfer_Active, tb_TX_Error, tb_Get_TX_Packet_Data
	
	// Test Bench Verification Signals
	integer tb_test_case_num;
	reg tb_Dplus_Out_prev, tb_Dminus_Out_prev;
	reg tb_expected_Dplus_Out, tb_expected_Dminus_Out, tb_expected_TX_Transfer_Active, tb_expected_TX_Error, tb_expected_Get_TX_Packet_Data;
	
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
	task decode_output;
		output logic EOP;
		output logic Dorig; // Note: Dorig means nothing if EOP is asserted
	begin
		EOP = ((tb_Dplus_Out == 1'b1) && (tb_Dminus_Out == 1'b1)) ? 1'b1 : 1'b0;
		Dorig = ((tb_Dplus_Out == tb_Dplus_Out_prev) && (tb_Dminus_Out == tb_Dminus_Out_prev)) ? 1'b1 : 1'b0;
	end
	endtask
	
	// Tasks for Checking USB-TX's Outputs
	// Task to check 'sync' byte
	task check_sync;
	begin
		logic [7:0] eop_byte;
		logic [7:0] sync_byte;
		
		// Record output 'sync' byte
		integer i;
		for (i = 0; i < 8; i++) begin
			@(negedge tb_clk);
			decode_output(.EOP(eop_byte[i]), .Dorig(sync_byte[i]));
		end
		
		// Check if EOP was ever asserted
		assert(eop_byte != 8'd0) $error("Test case %0d: EOP falsely set during 'sync' byte", tb_test_case_num);
		
		// Check if correct 'sync' byte outputted
		assert(sync_byte == 8'b00000001)
			$info("Test case %0d: Correct 'sync' byte outputted", tb_test_case_num);
		else
			$error("Test case %0d: Incorrect 'sync' byte outputted (Expected=0b%b, Actual:0b%b)", tb_test_case_num, 8'b00000001, sync_byte);
		
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
			decode_output(.EOP(eop_byte[i]), .Dorig(pid_byte[i]));
		end
		
		// Check if EOP was ever asserted
		assert(eop_byte != 8'd0) $error("Test case %0d: EOP falsely set during 'pid' byte", tb_test_case_num);
		
		// Check if correct 'pid' byte outputted
		assert(pid_byte == expected_pid_byte)
			$info("Test case %0d: Correct 'pid' byte outputted", tb_test_case_num);
		else
			$error("Test case %0d: Incorrect 'pid' byte outputted (Expected=0b%b, Actual:0b%b)", tb_test_case_num, expected_pid_byte, pid_byte);
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
			decode_output(.EOP(eop_bytes[i]), .Dorig(crc_bytes[i]));
		end
		
		// Check if EOP was ever asserted
		assert(eop_bytes != 16'd0) $error("Test case %0d: EOP falsely set during CRC", tb_test_case_num);
		
		// Check if correct 'pid' byte outputted
		assert(crc_bytes == expected_crc)
			$info("Test case %0d: Correct CRC outputted", tb_test_case_num);
		else
			$error("Test case %0d: Incorrect CRC outputted (Expected=0b%b, Actual:0b%b)", tb_test_case_num, expected_pid_byte, pid_byte);
	end
	endtask
	
	// Task to check 'EOP'
	task check_eop;
	begin
		logic EOP;
	
		// Check if EOP is asserted for first clock cycle
		@(negedge tb_clk);
		decode_output(.EOP(EOP));
		assert(EOP == 1'b1)
			$info("Test case %0d: Correct EOP asserted for first clock cycle", tb_test_case_num);
		else
			$error("Test case %0d: Incorrect EOP unasserted for first clock cycle", tb_test_case_num);
			
		// Check if EOP is asserted for second clock cycle
		@(negedge tb_clk);
		decode_output(.EOP(EOP));
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
		// Initialize all test inputs
		tb_n_rst = 1'b1;
		
		#(0.1);
		
		// **************************************************
		// Test Case 1: Power-on Reset of DUT
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		
		
		// **************************************************
		// Test Case 2: Nominal Packet Transmission - ACK
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
		// **************************************************
		// Test Case 3: Nominal Packet Transmission - NAK
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
		// **************************************************
		// Test Case 4: Nominal Packet Transmission - DATA0 (0 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
		// **************************************************
		// Test Case 5: Nominal Packet Transmission - DATA0 (1 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
		// **************************************************
		// Test Case 6: Nominal Packet Transmission - DATA0 (32 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
		// **************************************************
		// Test Case 7: Nominal Packet Transmission - DATA0 (64 bytes of data)
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
		// **************************************************
		// Test Case 8: Nominal Packet Transmission - STALL
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
		// **************************************************
		// Test Case 9: Bit-Stuffing at Beginning of DATA0 Packet
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
		// **************************************************
		// Test Case 10: Bit-Stuffing at Middle of DATA0 Packet
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
		// **************************************************
		// Test Case 11: Bit-Stuffing at End of DATA0 Packet
		// **************************************************
		tb_test_num = tb_test_num + 1;
		tb_test_case = "";
		//TODO: Reset to inactive values
		reset_dut();
		
	end
endmodule
