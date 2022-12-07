`default_nettype none `timescale 1ns / 10ps
`include "source/states.sv"

class address_gen;
    bit write = 0;
    bit [1:0] size = 0;

    rand bit [3:0] addr1;
    rand bit [3:0] addr2;
    rand bit [31:0] data;

    constraint same {
        (size == 0) -> addr1 == addr2;
        (size == 1) -> addr1[3:1] == addr2[3:1];
        (size == 2) -> addr1[3:2] == addr2[3:2];
    }

    constraint align {
        (size == 1) -> addr1[0] == 0;
        (size == 2) -> addr1[1:0] == 0;
    }

    constraint valid_write {
        (write == 1 && size < 2) -> addr1 inside {[0 : 3], ['hc : 'hd]};
        (write == 1 && size >= 2) -> addr1 inside {[0 : 3], ['hc : 'hf]};
    }

    constraint invalid_write {
        (write == 1 && size == 0) -> addr1 inside {['h9 : 'hb], ['he : 'hf]};
        (write == 1 && size == 1) -> addr1 inside {['ha : 'hb], ['he : 'hf]};
        (write == 1 && size >= 2) -> addr1 inside {[4 : 'hb]};
    }

    constraint normal_register {addr1 inside {['h4 : 'hf]};}

    constraint write_to_cd {
        (addr1 == 'hc) -> data[31:16] == 0;
        (addr1 == 'hc) -> data[7] == 1;
        (addr1 == 'hd) -> data[31:8] == 0;
    }

    constraint data_size {
        (size == 0) -> data[31:7] == 0;
        (size == 1) -> data[31:16] == 0;
    }
endclass

class ahb_bus;
    typedef struct {
        logic [31:0] data;
        logic [3:0] addr;
        logic [1:0] size;
        logic err, write, sel;
    } ahb_packet;

    ahb_packet q[$];

    static logic clk;

    // ahb inputs
    static logic hsel = 0;
    static logic [3:0] haddr = 0;
    static logic [1:0] hsize = 0, htrans = 0;
    static logic hwrite = 0;
    static logic [31:0] hwdata = 0;
    // ahb outputs
    static logic [31:0] hrdata;
    static logic hresp, hready;

    function void add(input logic [31:0] data, input logic [3:0] addr,
                      logic [1:0] size = 2, logic err = 0, logic write = 0,
                      logic sel = 1);
        this.q.push_back('{data: data, addr: addr, size: size, err: err,
                         write: write, sel: sel});
    endfunction

    task sendall();
        this.execute(this.q.size());
    endtask

    task execute(input int num = 1);
        ahb_packet prev;
        ahb_packet cur;

        if (num > this.q.size()) num = this.q.size();
        if (num < 1) return;

        prev = this.q.pop_front();

        @(negedge this.clk);
        this.set_outputs_address(prev);
        this.htrans = BUSY;
        @(posedge this.clk);

        for (int i = 1; i < num; i++) begin
            @(negedge this.clk);
            this.check_err(prev);
            cur = this.q.pop_front();
            this.set_outputs_address(cur);
            this.set_outputs_data(prev);

            @(posedge this.clk);
            while (!hready) @(posedge this.clk);

            #(0.1);
            this.check(prev);
            prev = cur;
        end

        // last one still needs to go through data phase
        @(negedge this.clk);
        this.set_outputs_data(prev);
        @(posedge this.clk);
        while (!hready) @(posedge this.clk);

        @(negedge this.clk);
        this.check(prev);
        this.reset();
    endtask

    function void set_outputs_address(input ahb_packet pak);
        this.hsel   = pak.sel;
        this.haddr  = pak.addr;
        this.hsize  = pak.size;
        this.hwrite = pak.write;
    endfunction

    function void set_outputs_data(input ahb_packet pak);
        if (pak.write) this.hwdata = pak.data;
    endfunction

    function reset();
        this.hsel   = 0;
        this.haddr  = 0;
        this.hsize  = 0;
        this.hwrite = 0;
        this.hwdata = 0;
        this.htrans = IDLE;
    endfunction

    function void check(input ahb_packet pak);
        if (!pak.sel) begin
            assert (this.hrdata == 0)
            else
                $error(
                    "Incorrect hrdata response at time %t (expected 0x00000000, got 0x%08x)",
                    $time,
                    this.hrdata
                );
            return;
        end

        if (pak.write == 0) begin
            assert (this.hrdata == pak.data)
            else
                $error(
                    "Incorrect hrdata response at time %t (expected 0x%08x, got 0x%08x)",
                    $time,
                    pak.data,
                    this.hrdata
                );
        end
    endfunction

    function void check_err(input ahb_packet pak);
        if (!pak.sel)
            assert (this.hresp == 0)
            else
                $error(
                    "Incorrect hresp response at time %t (expected 0, got %b)",
                    $time,
                    this.hresp
                );
        else
            assert (this.hresp == pak.err)
            else
                $error(
                    "Incorrect hresp response at time %t (expected %b, got %b)",
                    $time,
                    pak.err,
                    this.hresp
                );
    endfunction
endclass

module tb_ahb_slave ();
    // timing constants
    localparam time CLK_PERIOD = 10ns;
    // Sizing related constants
    // general constants
    localparam bit VERBOSE = 0;

    // testbench signals
    int test_num;
    string test_case;
    string subtest_case;

    // general inputs
    logic clk, n_rst;
    // general outputs
    logic d_mode;
    // ahb inputs
    logic hsel;
    logic [3:0] haddr;
    logic [2:0] hburst;
    logic [1:0] hsize, htrans;
    logic hwrite;
    logic [31:0] hwdata;
    // ahb outputs
    logic [31:0] hrdata;
    logic hresp, hready;
    // rx inputs
    logic [3:0] rx_packet;
    logic rx_data_ready, rx_transfer_active, rx_error;
    // tx inputs
    logic tx_transfer_active, tx_error;
    // tx outputs
    logic [2:0] tx_packet;
    logic tx_start;
    // data buffer inputs
    logic [31:0] rx_data;
    logic [7:0] buffer_occupancy;
    // data buffer outputs
    logic [1:0] get_rx_data, store_tx_data;
    logic [31:0] tx_data;
    logic clear_data_buffer;

    address_gen rng;
    ahb_bus bus = new;

    assign bus.clk    = clk;
    assign hsel       = bus.hsel;
    assign haddr      = bus.haddr;
    assign htrans     = bus.htrans;
    assign hsize      = bus.hsize;
    assign hwrite     = bus.hwrite;
    assign hwdata     = bus.hwdata;
    assign bus.hrdata = hrdata;
    assign bus.hresp  = hresp;
    assign bus.hready = hready;

    ahb_slave DUT (.*);

    task reset_dut();
        n_rst = 1'b0;
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        n_rst = 1'b1;
        @(posedge clk);
        @(posedge clk);
    endtask

    task init_usb_inputs();
        {
            n_rst, rx_packet, rx_data_ready, rx_transfer_active, rx_error,
            tx_transfer_active, tx_error, rx_data, buffer_occupancy
        } = '0;
    endtask

    task new_test(string name = "");
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        test_case    = name;
        subtest_case = "";
        test_num     = test_num + 1;
    endtask

    /* svlint off legacy_always */
    /* svlint off level_sensitive_always */
    always begin : CLK_GEN
        clk = 1'b0;
        #(CLK_PERIOD / 2.0);
        clk = 1'b1;
        #(CLK_PERIOD / 2.0);
    end
    /* svlint on level_sensitive_always */
    /* svlint on legacy_always */

    initial begin
        $timeformat(-9, 2, " ns", 20);
        rng = new;
        rng.invalid_write.constraint_mode(0);

        // Initialize Test Case Navigation Signals
        test_case = "Initialization";
        test_num  = -1;
        init_usb_inputs();

        @(posedge clk);

        // **************************************************
        // Reset
        // **************************************************
        new_test("Power on / Reset");

        n_rst = 0;
        @(negedge clk);

        // all outputs should be initialized to 0
        assert ({
            d_mode, hrdata, hresp,
            tx_start, get_rx_data, store_tx_data,
            clear_data_buffer
        } == '0);

        // **************************************************
        // Basic Write / Read
        // **************************************************
        new_test("Isolated single read / write");
        buffer_occupancy   = 1;
        tx_transfer_active = 1;
        reset_dut();


        rng.write    = 1;

        subtest_case = "4 byte";
        rng.size     = 2;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(2));
        bus.execute(1);
        @(negedge clk);
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(2));
        bus.execute(1);

        @(negedge clk);
        subtest_case = "2 byte";
        rng.size     = 1;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(1));
        bus.execute(1);
        @(negedge clk);
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(1));
        bus.execute(1);

        @(negedge clk);
        subtest_case = "1 byte";
        rng.size     = 0;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(0));
        bus.execute(1);
        @(negedge clk);
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(0));
        bus.execute(1);

        new_test("Overlapping single read / write");

        subtest_case = "4 byte";
        rng.size     = 2;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(2));
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(2));
        bus.execute(2);

        @(negedge clk);
        subtest_case = "2 byte";
        rng.size     = 1;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(1));
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(1));
        bus.execute(2);

        @(negedge clk);
        subtest_case = "1 byte";
        rng.size     = 0;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(0));
        bus.add(.addr(rng.addr2), .data(rng.data), .write(0), .size(0));
        bus.execute(2);

        rng.write_to_cd.constraint_mode(0);

        buffer_occupancy   = 0;
        tx_transfer_active = 0;

        // **************************************************
        // Bad Write
        // **************************************************
        new_test("Writing to read-only");
        reset_dut();

        rng.invalid_write.constraint_mode(1);
        rng.valid_write.constraint_mode(0);

        subtest_case = "4 byte";
        rng.size     = 2;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(2),
                .err(1));
        bus.add(.addr(rng.addr2), .data(0), .write(0), .size(2));
        bus.execute(2);

        subtest_case = "2 byte";
        rng.size     = 1;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(1),
                .err(1));
        bus.add(.addr(rng.addr2), .data(0), .write(0), .size(1));
        bus.execute(2);

        subtest_case = "1 byte";
        rng.size     = 0;
        assert (rng.randomize() == 1);
        bus.add(.addr(rng.addr1), .data(rng.data), .write(1), .size(0),
                .err(1));
        bus.add(.addr(rng.addr2), .data(0), .write(0), .size(0));
        bus.execute(2);

        rng.invalid_write.constraint_mode(0);
        rng.valid_write.constraint_mode(1);

        // wait out a few clock cycles before the final disable
        for (int i = 0; i < 20; i++) @(posedge clk);
        // disable CLK_GEN;
    end
endmodule
