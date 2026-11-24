`timescale 1ns/1ps
`default_nettype none

module minisoc_memory_tb;

    // -------------------------------------------------------------------------
    // Clocks (assíncronos entre si, para estressar a troca de ownership)
    // -------------------------------------------------------------------------
    logic mem_clk = 1'b0;
    logic aes_clk = 1'b0;
    always #5.0  mem_clk = ~mem_clk;    // 100 MHz
    always #2.5  aes_clk = ~aes_clk;    // 200 MHz

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic [31:0] mem_i_data = '0;
    logic        mem_i_wr_en = 1'b0;
    logic [9:0]  mem_i_addr  = '0;
    logic [31:0] mem_o_data;

    logic [9:0]  aes_addr  = '0;
    logic [31:0] aes_wdata = '0;
    logic        aes_wr_en = 1'b0;
    logic [31:0] aes_rdata;

    logic        mem_sel_aes = 1'b0;

    minisoc_memory dut (
        .mem_clk, .mem_i_data, .mem_i_wr_en, .mem_i_addr, .mem_o_data,
        .aes_clk, .aes_addr, .aes_wdata, .aes_wr_en, .aes_rdata,
        .mem_sel_aes
    );

    // -------------------------------------------------------------------------
    // Helpers (drivers em negedge; amostram após posedge + #1)
    // -------------------------------------------------------------------------
    int errors = 0;

    task automatic ext_write(input logic [9:0] a, input logic [31:0] d);
        @(negedge mem_clk);
        mem_i_addr  = a;
        mem_i_data  = d;
        mem_i_wr_en = 1'b1;
        @(negedge mem_clk);
        mem_i_wr_en = 1'b0;
    endtask

    task automatic ext_read(input logic [9:0] a, output logic [31:0] d);
        @(negedge mem_clk);
        mem_i_addr  = a;
        mem_i_wr_en = 1'b0;
        @(posedge mem_clk);
        #1 d = mem_o_data;
    endtask

    task automatic aes_write(input logic [9:0] a, input logic [31:0] d);
        @(negedge aes_clk);
        aes_addr  = a;
        aes_wdata = d;
        aes_wr_en = 1'b1;
        @(negedge aes_clk);
        aes_wr_en = 1'b0;
    endtask

    task automatic aes_read(input logic [9:0] a, output logic [31:0] d);
        @(negedge aes_clk);
        aes_addr  = a;
        aes_wr_en = 1'b0;
        @(posedge aes_clk);
        #1 d = aes_rdata;
    endtask

    logic [31:0] rd;

    // -------------------------------------------------------------------------
    // Sequência
    // -------------------------------------------------------------------------
    initial begin
        $display("=== minisoc_memory TB ===");

        // --- T1: external owner ---------------------------------------------
        $display("[T1] External write/read");
        mem_sel_aes = 1'b0;
        @(posedge mem_clk); @(posedge mem_clk);

        ext_write(10'd0,    32'hDEAD_BEEF);
        ext_write(10'd1,    32'hCAFE_BABE);
        ext_write(10'd1023, 32'hA5A5_A5A5);

        ext_read(10'd0,    rd); if (rd !== 32'hDEAD_BEEF) begin $error("[T1] addr0   got %h", rd); errors++; end
        ext_read(10'd1,    rd); if (rd !== 32'hCAFE_BABE) begin $error("[T1] addr1   got %h", rd); errors++; end
        ext_read(10'd1023, rd); if (rd !== 32'hA5A5_A5A5) begin $error("[T1] addr1023 got %h", rd); errors++; end

        // --- T2: switch to AES owner ----------------------------------------
        $display("[T2] Switch to AES owner");
        @(negedge mem_clk); @(negedge aes_clk);
        mem_sel_aes = 1'b1;
        repeat (2) @(posedge aes_clk);

        // AES escreve em 0 e 1
        aes_write(10'd0, 32'h1111_1111);
        aes_write(10'd1, 32'h2222_2222);

        // Lê de volta o que AES escreveu
        aes_read(10'd0, rd); if (rd !== 32'h1111_1111) begin $error("[T2] addr0 got %h", rd); errors++; end
        aes_read(10'd1, rd); if (rd !== 32'h2222_2222) begin $error("[T2] addr1 got %h", rd); errors++; end

        // Lê de volta o que o externo escreveu antes (addr 1023)
        aes_read(10'd1023, rd); if (rd !== 32'hA5A5_A5A5) begin $error("[T2] addr1023 got %h", rd); errors++; end

        // --- T3: switch back to external owner -------------------------------
        $display("[T3] Switch back to external owner");
        @(negedge aes_clk); @(negedge mem_clk);
        mem_sel_aes = 1'b0;
        repeat (2) @(posedge mem_clk);

        ext_read(10'd0, rd); if (rd !== 32'h1111_1111) begin $error("[T3] addr0 got %h", rd); errors++; end
        ext_read(10'd1, rd); if (rd !== 32'h2222_2222) begin $error("[T3] addr1 got %h", rd); errors++; end

        // --- Resultado -------------------------------------------------------
        if (errors == 0) $display("=== ALL PASS ===");
        else             $display("=== FAIL: %0d error(s) ===", errors);
        $finish;
    end

    initial begin
        $fsdbDumpfile("mem.fsdb");
        $fsdbDumpvars(0, minisoc_memory_tb);
        #200_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire