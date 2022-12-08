`default_nettype none

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

    task execute(input int num = -1);
        ahb_packet prev;
        ahb_packet cur;

        if (num > this.q.size() || num < 0) num = this.q.size();
        if (num == 0) return;

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
