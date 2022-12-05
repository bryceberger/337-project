// File name:       usb_tx.sv
// Created:         12/2/2022
// Author:          Trevor Moorman
// Group number:    5
// Version:         1.0 Initial Design Entry
// Description:     USB TX Module of USB Full-Speed Bulk-Transfer Endpoint AHB-Lite SoC Module

module usb_tx
(
    input wire clk, n_rst, TX_Start,
    input wire [1:0] TX_Packet,
    input wire [6:0] Buffer_Occupancy,
    input wire [7:0] TX_Packet_Data,
    output reg Dplus_Out, Dminus_Out, TX_Transfer_Active, TX_Error, Get_TX_Packet_Data
);
    localparam [1:0] TX_PACKET_DATA0 = 2'd0;
    localparam [1:0] TX_PACKET_ACK = 2'd1;
    localparam [1:0] TX_PACKET_NAK = 2'd2;
    localparam [1:0] TX_PACKET_STALL = 2'd3;

    // Control FSM
    localparam [3:0]
        idle = 4'd0,
        eidle = 4'd1,
        sync = 4'd2,
        pid = 4'd3,
        data = 4'd4,
        crc1 = 4'd5,
        crc2 = 4'd6,
        eof1 = 4'd7,
        eof2 = 4'd8;

    reg [2:0] state, nxt_state;
    reg syncEn, pidEn, dataEn, crcEn, eofEn; // May want to just use the current state itself rather than these enable signals

    always_ff @(negedge n_rst, posedge clk) begin
        if (!n_rst)
            state <= idle;
        else
            state <= nxt_state;
    end

    always_comb begin
        nxt_state = state;

        case(state)
            idle: begin
                if (TX_Start == 1'b1) nxt_state = sync;
            end
            eidle: begin
                if (TX_Start == 1'b1) nxt_state = sync;
            end
            sync: begin
                if (endByte == 1'b1) nxt_state = pid;
            end
            pid: begin
                if (endByte == 1'b1) begin
                    if (TX_Packet == TX_PACKET_DATA0) begin
                        if (Buffer_Occupancy == 7'd0) nxt_state = eidle;
                        else nxt_state = data;
                    end
                    else nxt_state = eof1;
                end
            end
            data: begin
                if ((endByte == 1'b1) && (Buffer_Occupancy == 7'd0)) nxt_state = crc1;
            end
            crc1: begin
                if (endByte == 1'b1) nxt_state = crc2;
            end
            crc2: begin
                if (endByte == 1'b1) nxt_state = eof1;
            end
            eof1: begin
                nxt_state = eof2;
            end
            eof2: begin
                nxt_state = idle;
            end
        endcase
    end

    always_comb begin
        TX_Transfer_Active = 1'b0;
        TX_Error = 1'b0;
        syncEn = 1'b0;
        pidEn = 1'b0;
        dataEn = 1'b0;
        crcEn = 1'b0;
        eofEn = 1'b0;

        case(state)
            // idle: do nothing
            eidle: begin
                TX_Error = 1'b1;
            end
            sync: begin
                TX_Transfer_Active = 1'b1;
                syncEn = 1'b1;
            end
            pid: begin
                TX_Transfer_Active = 1'b1;
                pidEn = 1'b1;
            end
            data: begin
                TX_Transfer_Active = 1'b1;
                dataEn = 1'b1;
            end
            crc1: begin
                TX_Transfer_Active = 1'b1;
                crcEn = 1'b1;
            end
            crc2: begin
                TX_Transfer_Active = 1'b1;
                crcEn = 1'b1;
            end
            eof1: begin
                TX_Transfer_Active = 1'b1;
                eofEn = 1'b1;
            end
            eof2: begin
                TX_Transfer_Active = 1'b1;
                eofEn = 1'b1;
            end
        endcase
    end

    // Bit Counter
    reg endByte;
    reg [2:0] bitNum, nxt_bitNum;

    always_ff @(negedge n_rst, posedge clk) begin
        if (!n_rst) begin
            bitNum <= 3'd0;
        end
        else begin
            bitNum <= nxt_bitNum;
        end
    end

    always_comb begin
        nxt_bitNum = bitNum;
        endByte = 1'b0;
        Get_TX_Packet_Data = 1'b0;

        if (shiftEn == 1'b1) begin
            if (syncEn == 1'b1) nxt_bitNum = 3'd0;
            else if (stuffEn == 1'b1) nxt_bitNum = bitNum;
            else if (bitNum == 3'd7) nxt_bitNum = 3'd0;
            else nxt_bitNum = bitNum + 1;

            if (bitNum == 3'd7) begin
                endByte = 1'b1;
                Get_TX_Packet_Data = dataEn;
            end
        end
    end

    // Clock Divider
    reg shiftEn;
    //TODO

    // Shift Register
    reg nxtBit;

    flex_pts_sr #(
        .NUM_BITS(8),
        .SHIFT_MSB(1'b0) // Make sure endianness is correct
    )
    SHIFT_REGISTER (
        .clk(clk),
        .n_rst(n_rst),
        .shift_enable(shiftEn),
        .load_enable(Get_TX_Packet_Data), // May need to be delayed 1 clock cycle
        .parallel_in(TX_Packet_Data),
        .serial_out(nxtBit)
    );

    // Bit-Stuffer
    reg enStuff;
    reg [2:0] numOne, nxt_numOne;

    always_ff @(negedge n_rst, posedge clk) begin
        if (!n_rst)
            numOne <= 3'd0;
        else
            numOne <= nxt_numOne;
    end

    always_comb begin
        nxt_numOne = numOne;

        if shiftEn begin
            if dataEn begin
                if nxtBit begin
                    if (numOne == 3'd5) nxt_numOne = 3'd0;
                    else nxt_numOne = numOne + 1;
                end
                else nxt_numOne = 3'd0;
            end
            else if crcEn begin
                if crcBit begin
                    if (numOne == 3'd5) nxt_numOne = 3'd0;
                    else nxt_numOne = numOne + 1;
                end
                else nxt_numOne = 3'd0;
            end
            else nxt_numOne = 3'd2;
        end
    end

    always_comb begin
        enStuff = 1'b0;

        if ((numOne == 3'd5) && (dataEn == 1'b1) && (nxtBit == 1'b1)) begin
            enStuff = 1'b1;
        end
        else if ((numOne == 3'd5) && (crcEn == 1'b1) && (crcBit == 1'b1)) begin
            enStuff = 1'b1;
        end
    end

    // Encoder
    reg nxt_Dplus_Out, nxt_Dminus_Out;

    always_ff @(negedge n_rst, posedge clk) begin
        if (!n_rst)
            Dplus_Out <= 1'b1;
            Dminus_Out <= 1'b0;
        else
            Dplus_Out <= nxt_Dplus_Out;
            Dminus_Out <= nxt_Dminus_Out;
    end

    always_comb begin
        {nxt_Dplus_Out, nxt_Dminus_Out} = {Dplus_Out, Dminus_Out};

        if (shiftEn == 1'b1) begin
            if (stuffEn == 1'b1) begin
                {nxt_Dplus_Out, nxt_Dminus_Out} = ~{Dplus_Out, Dminus_Out};
            end
            else if (syncEn == 1'b1) begin
                case(bitNum)
                    3'd0, 3'd1, 3'd2, 3'd3, 3'd4, 3'd5, 3'd6: begin
                        {nxt_Dplus_Out, nxt_Dminus_Out} = ~{Dplus_Out, Dminus_Out};
                    end
                    3'd7: begin
                        {nxt_Dplus_Out, nxt_Dminus_Out} = {Dplus_Out, Dminus_Out};
                    end
                endcase
            end
            else if (pidEn == 1'b1) begin
                case(TX_Packet)
                    TX_PACKET_DATA0: begin // 11000011
                        // 1
                        3'd0, 3'd1, 3'd6, 3'd7: begin
                            {nxt_Dplus_Out, nxt_Dminus_Out} = {Dplus_Out, Dminus_Out};
                        end
                        // 0
                        3'd2, 3'd3, 3'd4, 3'd5: begin
                            {nxt_Dplus_Out, nxt_Dminus_Out} = ~{Dplus_Out, Dminus_Out};
                        end
                    end
                    TX_PACKET_ACK: begin // 01001011
                        // 1
                        3'd1, 3'd4, 3'd6, 3'd7: begin
                            {nxt_Dplus_Out, nxt_Dminus_Out} = {Dplus_Out, Dminus_Out};
                        end
                        // 0
                        3'd0, 3'd2, 3'd3, 3'd5: begin
                            {nxt_Dplus_Out, nxt_Dminus_Out} = ~{Dplus_Out, Dminus_Out};
                        end
                    end
                    TX_PACKET_NAK: begin // 01011010
                        // 1
                        3'd1, 3'd3, 3'd4, 3'd6: begin
                            {nxt_Dplus_Out, nxt_Dminus_Out} = {Dplus_Out, Dminus_Out};
                        end
                        // 0
                        3'd0, 3'd2, 3'd5, 3'd7: begin
                            {nxt_Dplus_Out, nxt_Dminus_Out} = ~{Dplus_Out, Dminus_Out};
                        end
                    end
                    TX_PACKET_STALL: begin // 01111000
                        // 1
                        3'd1, 3'd2, 3'd3, 3'd4: begin
                            {nxt_Dplus_Out, nxt_Dminus_Out} = {Dplus_Out, Dminus_Out};
                        end
                        // 0
                        3'd0, 3'd5, 3'd6, 3'd7: begin
                            {nxt_Dplus_Out, nxt_Dminus_Out} = ~{Dplus_Out, Dminus_Out};
                        end
                    end
                endcase
            end
            else if (dataEn == 1'b1) begin
                if (nxtBit == 1'b0) {nxt_Dplus_Out, nxt_Dminus_Out} = ~{Dplus_Out, Dminus_Out};
            end
            else begin
                {nxt_Dplus_Out, nxt_Dminus_Out} = 2'b0;
            end
        end
    end

    // CRC-16
    reg crcBit;
    //TODO

endmodule
