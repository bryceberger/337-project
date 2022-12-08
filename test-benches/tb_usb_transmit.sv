class tb_usb_transmit;
    typedef union tagged {
        byte usb_data_byte;
        struct {
            byte eop;
            byte data;
            byte num_bits;
        } usb_data_eop;
    } USB_data;

    USB_data data_queue[$];
    static logic dp = 1'b1, dm = 1'b0;

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
            dp = 1'b0;
            dm = 1'b0;
            #(period);
            return;
        end

        dp ^= ~b;
        dm = ~dp;
        #(period);

        if (b == 1'b1)
            ones++;
        else
            ones = 0;

        if (ones == 6) begin
            ones = 0;
            send_usb_bit(period, 1'b0);
        end
    endtask

    task send_usb_packet(
        input time period = (250/3) * 1ns // validate from 82 to 84 ns
    );
        USB_data usb_data;
        automatic bit bus_state = 1'b1;
        automatic int ones = 0;
        while (usb_bytes_remaining() > 0) begin
            usb_data = dequeue_usb_byte();
            case (usb_data) matches
                tagged usb_data_byte .b: begin
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
        USB_data dat;
        automatic byte pid_byte = {~pid, pid};
        dat = tagged usb_data_byte (8'h80);
        enqueue_usb_byte(dat);
        dat = tagged usb_data_byte (pid_byte);
        enqueue_usb_byte(dat);
        for (int i = 0; i < n_bytes; i++) begin
            dat = tagged usb_data_byte (bytes[i]);
            enqueue_usb_byte(dat);
        end
        dat = tagged usb_data_eop ('{8'h03, 8'h00, 3});
        enqueue_usb_byte(dat);
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
        for (int i = 0; i < 11; i++) begin
            xr = data[i] ^ crc[4];
            crc = {crc[3:2], crc[1] ^ xr, crc[0], xr};
        end

        // send data
        bytes = { << byte { {{<<{~crc}}, endpoint[3:1]}, {endpoint[0], address} }};
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

        enqueue_usb_packet(
            pid, n_bytes + 2,
            { data, { << {~crc[15:8]} }, { << {~crc[7:0]} } }
        );
    endtask

    task enqueue_usb_handshake(input bit [1:0] h_type); // ACK, NAK, STALL
        automatic bit [3:0] pid = { ^h_type, h_type[1], 2'b10 };
        enqueue_usb_packet(pid, 0, {});
    endtask
endclass
