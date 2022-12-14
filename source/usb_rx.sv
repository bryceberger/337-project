module usb_rx (
    input wire clk, input wire n_rst,
    // USB input lines
    input wire dp, input wire dm,
    // Outputs to AHB-lite interface
    output wire [2:0] rx_packet,
    output reg rx_data_ready,
    output wire rx_transfer_active,
    output wire rx_error,
    // I/O from FIFO
    output wire flush, output reg store_rx_packet_data,
    output reg [7:0] rx_packet_data,
    input wire [6:0] buffer_occupancy
);

    // synchronize data
    logic n_rdata, rdata, l_rdata;
    assign n_rdata = dp;
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) {l_rdata, rdata} = 2'b11;
        else {l_rdata, rdata} = {rdata, n_rdata};

    // synchronize EOP
    logic n_eop, eop, l_eop;
    assign n_eop = dp == dm;
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) {l_eop, eop} = 2'b00;
        else {l_eop, eop} = {eop, n_eop};

    // edge detection
    logic edg;
    assign edg = (eop ^ l_eop) || (rdata ^ l_rdata);

    // timer for deciding when to shift based on edges
    logic [3:0] count, n_count;
    assign n_count = count == 0 ? 8 : count - 1;
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) count <= 8;
        else count <= edg ? 3 : n_count;

    // decide when to shift
    logic raw_shift, shift, skip;
    assign raw_shift = count == 0;
    assign shift = raw_shift && !skip;

    // keep track of previously shifted raw data
    logic prev_rdata;
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) prev_rdata <= 1'b1;
        else prev_rdata <= raw_shift ? rdata : prev_rdata;

    // keep track of number of ones on the bus
    logic [2:0] ones, n_ones;
    assign n_ones = prev_rdata == rdata ? ones + 1 : 0;
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) ones <= 0;
        else ones <= raw_shift ? n_ones : ones;
    // TODO RX error if ones is 7

    // decode data from raw data
    logic data;
    assign data = rdata == prev_rdata;

    // shift register for bytes of data
    assign skip = ones >= 6;
    logic [7:0] sr;
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) sr <= 8'h00;
        else sr <= shift ? {data, sr[7:1]} : sr;

    // count bits received
    logic [3:0] bit_count, n_bit_count;
    assign n_bit_count = shift ? bit_count + 1 : bit_count;
    logic bit_count_clear; // clear control
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) bit_count = 4'h0;
        else bit_count = bit_count_clear ? 0 : n_bit_count;

    logic EOP;
    assign EOP = eop && shift;

    enum bit [2:0] {
        IDLE, READ_SP, TOKEN, DATA, EOP1, EOP2, ERROR, ERR2
    } state, n_state;

    bit n_data_ready;
    bit [2:0] packet, n_packet;
    bit active, n_active;

    // clear count, read sync, read PID
    bit [1:0] sp_state, n_sp_state;
    // TODO
    bit [1:0] r_state, n_r_state;

    logic token_pid, data_pid, ack_pid, nack_pid, stall_pid;
    assign token_pid = sr[2:0] == 2'b001;
    assign data_pid = sr[2:0] == 3'b011;
    assign ack_pid =   sr[3:0] == 4'b0010;
    assign nack_pid =  sr[3:0] == 4'b1010;
    assign stall_pid = sr[3:0] == 4'b1110;

    logic crc5v, crc16v, clear;
    crc5 CRC5 (.valid(crc5v), .crc(), .*);
    crc16 CRC16 (.valid(crc16v), .crc(), .*);

    assign clear = state == READ_SP;

    always_comb begin
        n_state = state;
        n_data_ready = state != READ_SP ? rx_data_ready : 0;
        n_sp_state = state == READ_SP || state == EOP2 ? sp_state : 0;
        n_r_state = state == TOKEN || state == DATA ? r_state : 0;
        n_packet = state == READ_SP ? 3'b100 : packet;
        n_active = active;
        if (state == EOP1 || state == EOP2) begin
            if (EOP && state == EOP1)
                n_state = EOP2;
            else if (EOP && state == EOP2 && !sp_state)
                n_sp_state = 1;
            else if (shift && rdata && state == EOP2 && sp_state)
                n_state = IDLE;
            else if (shift) n_state = ERROR;
        end
        else if (EOP) begin
            if (state == DATA && bit_count == 0) begin
                n_state = crc16v ? EOP2 : ERROR;
                n_data_ready = crc16v;
            end
            else
                n_state = ERROR;
        end
        else if (state == IDLE || state == ERROR) begin
            if (!rdata && !eop) n_state = READ_SP;
        end
        else if (state == READ_SP)
            case (sp_state)
                0: n_sp_state = 1; // clear bit count
                1: if (bit_count == 8)
                    if (sr == 8'h80)
                        n_sp_state = 2;
                    else
                        n_state = ERROR;
                2: if (bit_count == 0)
                    if (sr[3:0] != ~sr[7:4])
                        n_state = ERROR;
                    else if (token_pid) begin
                        n_state = TOKEN;
                        n_packet = {0, sr[3]};
                    end
                    else if (data_pid)
                        n_state = DATA;
                    else if (ack_pid) begin
                        n_state = EOP1;
                        n_packet = 2;
                    end
                    else if (nack_pid) begin
                        n_state = EOP1;
                        n_packet = 3;
                    end
                    else if (stall_pid)
                        n_state = EOP1;
                    else
                        n_state = ERROR;
            endcase
        else if (state == TOKEN)
            case (r_state)
                0: n_r_state = bit_count == 8;
                1: if (bit_count == 0)
                    n_state = crc5v ? EOP1 : ERROR;
            endcase
        else if (state == DATA)
            case (r_state)
                0: n_r_state = 1; // clear bit_count
                1: if (bit_count == 8) n_r_state = 2;
                2: n_r_state = 0; // store data
            endcase
        else n_state = ERROR;
    end

    assign bit_count_clear = state == READ_SP && sp_state == 0
        || state == DATA && r_state == 0;

    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst)
            {
                state, sp_state, r_state,
                rx_data_ready, packet, active
            } <= {
                IDLE, 2'b0, 2'b0,
                1'b0, 3'b000, 1'b1
            };
        else
            {
                state, sp_state, r_state,
                rx_data_ready, packet, active
            } <= {
                n_state, n_sp_state, n_r_state,
                n_data_ready, n_packet, n_active
            };

    assign rx_error = state == ERROR;
    assign flush = state == READ_SP;
    assign rx_transfer_active = !(state == IDLE || state == ERROR);

    bit push_data;
    assign push_data = state == DATA && r_state == 2;

    bit [1:0] delay_amount, d_delay_amount, n_delay_amount;
    assign d_delay_amount = push_data ? delay_amount - 1 : delay_amount;
    assign n_delay_amount = state == IDLE
        ? 2'd2
        : delay_amount == 0 ? 0 : d_delay_amount;
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) delay_amount <= 2'd2;
        else delay_amount <= n_delay_amount;

    byte bytes [3];
    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) bytes <= {0, 0, 0};
        else if (push_data)
            bytes <= {sr, bytes[0], bytes[1]};
        else
            bytes <= bytes;

    always_ff @(posedge clk, negedge n_rst)
        if (!n_rst) store_rx_packet_data <= 0;
        else store_rx_packet_data <= push_data && delay_amount == 0;

    assign rx_packet_data = bytes[2];

    // OUT, IN, ACK, NACK
    assign rx_packet = {rx_error || !active, 2'b0} | packet;

endmodule
