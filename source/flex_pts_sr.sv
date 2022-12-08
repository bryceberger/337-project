module flex_pts_sr #(
    parameter NUM_BITS  = 4,
    parameter SHIFT_MSB = 1
) (
    input logic clk,
    n_rst,
    shift_enable,
    load_enable,
    input logic [(NUM_BITS-1):0] parallel_in,
    output logic serial_out
);

    logic [(NUM_BITS-1):0] saved;

    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) saved <= -1;
        else if (load_enable) saved <= parallel_in;
        else if (shift_enable)
            if (SHIFT_MSB) saved <= {saved[(NUM_BITS-2):0], 1'b1};
            else saved <= {1'b1, saved[(NUM_BITS-1):1]};

    assign serial_out = SHIFT_MSB ? saved[NUM_BITS-1] : saved[0];

endmodule
