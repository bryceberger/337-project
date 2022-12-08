module flex_counter
#( parameter NUM_CNT_BITS = 4 )
(
	input logic clk, n_rst, clear, count_enable,
	input logic [(NUM_CNT_BITS-1):0] rollover_val,
	output logic [(NUM_CNT_BITS-1):0] count_out,
	output logic rollover_flag
);

always_ff @ (posedge clk, negedge n_rst) begin
	if (!n_rst) begin
		count_out <= 0;
		rollover_flag <= 0;
	end else if (clear) begin
		count_out <= 0;
		rollover_flag <= 0;
	end else if (count_enable) begin
		if (count_out == rollover_val) begin
			count_out <= 1;
			rollover_flag <= 0;
		end else if (count_out == rollover_val - 1) begin
			rollover_flag <= 1;
			count_out <= count_out + 1;
		end else begin
			count_out <= count_out + 1;
			rollover_flag <= 0;
		end
	end else begin
		count_out <= count_out;
		rollover_flag <= rollover_flag;
	end
end

endmodule
