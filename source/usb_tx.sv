`default_nettype none
// File name:       usb_tx.sv
// Created:         12/2/2022
// Author:          Trevor Moorman
// Group number:    5
// Version:         1.0 Initial Design Entry
// Description:     USB TX Module of USB Full-Speed Bulk-Transfer Endpoint AHB-Lite SoC Module

//TODO: CRC

module usb_tx (
    input var clk,
    input var n_rst,
    input var tx_start,
    input var [1:0] tx_packet,
    input var [6:0] buffer_occupancy,
    input var [7:0] tx_packet_data,
    output var dp,
    output var dm,
    output var tx_transfer_active,
    output var tx_error,
    output var get_tx_packet_data
);
    localparam bit [1:0] 
        TX_PACKET_DATA0 = 2'd0,
        TX_PACKET_ACK = 2'd1,
        TX_PACKET_NAK = 2'd2,
        TX_PACKET_STALL = 2'd3;

    // Clock Divider Variables
    reg shiftEn;
    reg [3:0] clockCnt;
    wire beginBitPeriod;
    assign beginBitPeriod = (clockCnt == 1'b1);

    // Control FSM Variables
    localparam bit [2:0]
        idle = 'd0,
        sync = 'd1,
        pid  = 'd2,
        data = 'd3,
        crc1 = 'd4,
        crc2 = 'd5,
        eof1 = 'd6,
        eof2 = 'd7;
    reg [2:0] state, nxt_state;
    reg
        syncEn,
        pidEn,
        dataEn,
        crcEn,
        eofEn; // May want to just use the current state itself rather than these enable signals

    // Bit Counter Variables
    reg endByte, prev_syncEn;
    reg [2:0] bitNum, nxt_bitNum;
    wire beginTransmit;
    assign beginTransmit = (prev_syncEn == 1'b0) && (syncEn == 1'b1);

    // Shift Register Variables
    reg nxtBit;

    // CRC-16 Variables
    reg crcBit;  // Output by a pts shift register filled with CRC subcircuit
    logic [15:0] crc_output;
    logic crc_clear, crc_shift;
    assign crc_shift = beginBitPeriod == 1 && dataEn;
    crc16 crc_mod (
        .*,
        .crc  (crc_output),
        .clear(crc_clear),
        .data (nxtBit),
        .shift(crc_shift),
        .valid()
    );

    flex_pts_sr #(
        .NUM_BITS (16),
        .SHIFT_MSB(1'b0)
    ) CRC_SHIFT_REGISTER (
        .*,
        .shift_enable(shiftEn),
        .load_enable (nxt_state == crc1),  // May need to be delayed 1 clock cycle
        .parallel_in (crc_output),
        .serial_out  (crcBit)
    );


    // Bit-Stuffer Variables
    reg stuffEn;
    reg [2:0] numOne, nxt_numOne;

    // Encoder Variables
    reg prev_dp, prev_dm;

    // Clock Divider
    flex_counter #(
        .NUM_CNT_BITS(4)
    ) CYCLE_COUNTER (
        .*,
        .clear(beginTransmit),
        .count_enable(1'b1),
        .count_out(clockCnt),
        .rollover_val(4'd8),
        .rollover_flag(shiftEn)
    );

    // Control FSM
    always_ff @(negedge n_rst, posedge clk)
        if (!n_rst) state <= idle;
        else state <= nxt_state;

    always_comb begin
        nxt_state = state;
        crc_clear = 0;

        case (state)
            idle: begin
                if (tx_start == 1'b1) nxt_state = sync;
            end
            sync: begin
                crc_clear = 1;
                if (endByte == 1'b1) nxt_state = pid;
            end
            pid: begin
                if (endByte == 1'b1) begin
                    if (tx_packet == TX_PACKET_DATA0 && buffer_occupancy)
                        nxt_state = data;
                    else if (tx_packet == TX_PACKET_DATA0) nxt_state = crc1;
                    else nxt_state = eof1;
                end
            end
            data: begin
                if ((endByte == 1'b1) && (buffer_occupancy == 7'd0))
                    nxt_state = crc1;
            end
            crc1: begin
                if (endByte == 1'b1) nxt_state = crc2;
            end
            crc2: begin
                if (endByte == 1'b1) nxt_state = eof1;
            end
            eof1: begin
                if (shiftEn == 1'b1) nxt_state = eof2;
            end
            eof2: begin
                if (shiftEn == 1'b1) nxt_state = idle;
            end
        endcase
    end

    always_comb begin
        tx_transfer_active = 1'b0;
        tx_error           = 1'b0;
        syncEn             = 1'b0;
        pidEn              = 1'b0;
        dataEn             = 1'b0;
        crcEn              = 1'b0;
        eofEn              = 1'b0;

        case (state)
            sync: begin
                tx_transfer_active = 1'b1;
                syncEn             = 1'b1;
            end
            pid: begin
                tx_transfer_active = 1'b1;
                pidEn              = 1'b1;
            end
            data: begin
                tx_transfer_active = 1'b1;
                dataEn             = 1'b1;
            end
            crc1: begin
                tx_transfer_active = 1'b1;
                crcEn              = 1'b1;
            end
            crc2: begin
                tx_transfer_active = 1'b1;
                crcEn              = 1'b1;
            end
            eof1: begin
                tx_transfer_active = 1'b1;
                eofEn              = 1'b1;
            end
            eof2: begin
                tx_transfer_active = 1'b1;
                eofEn              = 1'b1;
            end
            // idle: do nothing
            default: tx_transfer_active = 0;
        endcase
    end

    // Bit Counter
    always_ff @(negedge n_rst, posedge clk)
        if (!n_rst) begin
            bitNum      <= 3'd0;
            prev_syncEn <= 1'b0;
        end else begin
            bitNum      <= nxt_bitNum;
            prev_syncEn <= syncEn;
        end

    always_comb begin
        nxt_bitNum         = bitNum;
        endByte            = 1'b0;
        get_tx_packet_data = 1'b0;

        if (shiftEn == 1'b1) begin
            if (beginTransmit) nxt_bitNum = 3'd0;
            else if (stuffEn == 1'b1) nxt_bitNum = bitNum;
            else if (bitNum == 3'd7) nxt_bitNum = 3'd0;
            else nxt_bitNum = bitNum + 1;

            if (bitNum == 3'd7) begin
                endByte            = 1'b1;
                get_tx_packet_data = dataEn;
            end
        end
    end

    // Shift Register
    /*
    flex_pts_sr #(
        .NUM_BITS (8),
        .SHIFT_MSB(1'b0)  // Make sure endianness is correct
    ) SHIFT_REGISTER (
        .*,
        .shift_enable(shiftEn),
        .load_enable(((beginBitPeriod == 1'b1) && (bitNum == 3'd))),
        .parallel_in(tx_packet_data),
        .serial_out(nxtBit)
    );
    */
    assign nxtBit = tx_packet_data[bitNum];

    // Bit-Stuffer
    always_ff @(negedge n_rst, posedge clk)
        if (!n_rst) numOne <= 3'd0;
        else numOne <= nxt_numOne;

    logic stuff_source;
    assign stuff_source = dataEn ? nxtBit : crcEn ? crcBit : 0;

    always_comb
        if (shiftEn && stuff_source)
            if (numOne == 5) nxt_numOne = 0;
            else nxt_numOne = numOne + 1;
        else if (shiftEn) nxt_numOne = 0;
        else nxt_numOne = numOne;

    always_comb
        if (numOne == 5 && stuff_source == 1) stuffEn = 1'b1;
        else stuffEn = 1'b0;

    // Encoder
    always_ff @(negedge n_rst, posedge clk)
        if (!n_rst) {prev_dp, prev_dm} <= 2'b10;
        else {prev_dp, prev_dm} <= {dp, dm};

    always_comb
        if (beginBitPeriod == 1'b1) begin
        		{dp, dm} = {prev_dp, prev_dm};
            if (stuffEn == 1'b1) begin
                {dp, dm} = ~{prev_dp, prev_dm};
            end else if (syncEn == 1'b1) begin
                case (bitNum) inside
                    [0 : 6]: {dp, dm} = ~{prev_dp, prev_dm};
                    7: {dp, dm} = {prev_dp, prev_dm};
                endcase
            end else if (pidEn == 1'b1) begin
                case (tx_packet)
                    TX_PACKET_DATA0: begin  // 11000011
                        case (bitNum) inside
                            // 1
                            0, 1, 6, 7: {dp, dm} = {prev_dp, prev_dm};
                            // 0
                            [2 : 5]: {dp, dm} = ~{prev_dp, prev_dm};
                        endcase
                    end
                    TX_PACKET_ACK: begin  // 01001011
                        case (bitNum) inside
                            // 1
                            1, 4, 6, 7: {dp, dm} = {prev_dp, prev_dm};
                            // 0
                            0, 2, 3, 5: {dp, dm} = ~{prev_dp, prev_dm};
                        endcase
                    end
                    TX_PACKET_NAK: begin  // 01011010
                        case (bitNum) inside
                            // 1
                            1, 3, 4, 6: {dp, dm} = {prev_dp, prev_dm};
                            // 0
                            0, 2, 5, 7: {dp, dm} = ~{prev_dp, prev_dm};
                        endcase
                    end
                    default: begin  // TX_PACKET_STALL: begin  // 01111000
                        case (bitNum) inside
                            // 1
                            [1 : 4]: {dp, dm} = {prev_dp, prev_dm};
                            // 0
                            0, [5 : 7]: {dp, dm} = ~{prev_dp, prev_dm};
                        endcase
                    end
                endcase
            end else if (dataEn == 1'b1) begin
                if (nxtBit == 1'b0) {dp, dm} = ~{prev_dp, prev_dm};
            end else if (crcEn) begin
                if (crcBit == 0) {dp, dm} = ~{prev_dp, prev_dm};
            end else if (eofEn == 1'b1) begin
                {dp, dm} = 2'b0;
            end
        end else {dp, dm} = {prev_dp, prev_dm};
endmodule
