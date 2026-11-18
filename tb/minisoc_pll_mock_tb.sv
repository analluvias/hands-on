`timescale 1ps/1ps

module minisoc_pll_mock_tb;

    // Referência 2 GHz -> período 500 ps, half-period 250 ps
    localparam time CLK_HALF   = 250;
    localparam time CLK_PERIOD = 500;

    logic       clk;
    logic       rst_n;
    logic       pll_enable;
    logic [1:0] pll_div_sel;
    logic       pll_locked;
    logic       sys_clk;

    initial clk = 1'b0;
    always #(CLK_HALF) clk = ~clk;

    minisoc_pll_mock #(.LOCK_CYCLES(16)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .pll_enable  (pll_enable),
        .pll_div_sel (pll_div_sel),
        .pll_locked  (pll_locked),
        .sys_clk     (sys_clk)
    );

    // Monitor de bordas em sys_clk (ignora X)
    int sys_edges = 0;
    always @(sys_clk) if (!$isunknown(sys_clk)) sys_edges++;

    int errors = 0;
    task automatic expect(input string msg, input logic cond);
        if (!cond) begin
            $display("FAIL: %s", msg);
            errors++;
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    task automatic measure_period(output time period);
        time t1, t2;
        @(posedge sys_clk); t1 = $time;
        @(posedge sys_clk); t2 = $time;
        period = t2 - t1;
    endtask

    task automatic reset_and_enable(input logic [1:0] sel);
        rst_n       = 1'b0;
        pll_enable  = 1'b0;
        pll_div_sel = sel;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        pll_enable = 1'b1;
    endtask

    task automatic check_divisor(input logic [1:0] sel, input int div);
        time period, expected;
        reset_and_enable(sel);
        wait (pll_locked);
        @(posedge sys_clk);
        measure_period(period);
        expected = CLK_PERIOD * div;
        if (period != expected) begin
            $display("FAIL: div=%0d expected=%0t measured=%0t",
                     div, expected, period);
            errors++;
        end else begin
            $display("PASS: div=%0d period=%0t", div, period);
        end
    endtask

    initial begin

        $fsdbDumpfile("pll.fsdb");
        $fsdbDumpvars(0, minisoc_pll_mock_tb, "+all");

        rst_n       = 1'b0;
        pll_enable  = 1'b0;
        pll_div_sel = 2'b00;

        // T1: sys_clk silencioso antes de pll_enable
        repeat (8) @(posedge clk);
        expect("sys_clk silencioso antes de pll_enable", sys_edges == 0);

        // T2: enable sem lock -> sys_clk continua em 0
        rst_n      = 1'b1;
        pll_enable = 1'b1;
        repeat (4) @(posedge clk);   // < LOCK_CYCLES
        expect("pll_locked=0 antes de LOCK_CYCLES", !pll_locked);
        expect("sys_clk silencioso antes de locked", sys_edges == 0);

        // T3: após lock, sys_clk oscila
        wait (pll_locked);
        @(posedge sys_clk); @(posedge sys_clk);
        expect("sys_clk oscila após lock", sys_edges >= 2);

        // T4: os 4 divisores
        check_divisor(2'b00, 1);
        check_divisor(2'b01, 2);
        check_divisor(2'b10, 4);
        check_divisor(2'b11, 8);

        // T5: disable -> locked=0 e sys_clk silencia
        reset_and_enable(2'b00);
        wait (pll_locked);
        @(posedge sys_clk);
        pll_enable = 1'b0;
        repeat (4) @(posedge clk);
        expect("pll_locked=0 após disable", !pll_locked);
        sys_edges = 0;
        repeat (8) @(posedge clk);
        expect("sys_clk silencioso após disable", sys_edges == 0);

        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #1_000_000; // 1 us guard
        $fatal(1, "TIMEOUT");
    end

endmodule