// smoke test de integração
`timescale 1ns/1ps

module minisoc_spi_tb;

    // SPI master @ ~25 MHz (40 ns de período)
    localparam time T_SCLK_HALF = 20;
    localparam time T_CS_SETUP  = 20;
    localparam time T_CS_HOLD   = 20;
    localparam time T_CS_IDLE   = 100;

    // ---- DUT ports -------------------------------------------------------
    logic         spi_sclk;
    logic         spi_cs_n;
    logic         spi_mosi;
    logic         spi_miso;
    logic         clk;
    logic         rst_n;
    logic         status_busy;
    logic         status_done;
    logic         status_error;
    logic [8:0]   status_blocks_done;
    logic         pll_locked;
    logic [127:0] cfg_key;
    logic [127:0] cfg_iv;
    logic [63:0]  cfg_counter;
    logic [8:0]   cfg_num_blocks;
    logic [2:0]   cfg_mode;
    logic         cfg_decrypt;
    logic         cmd_start;
    logic [31:0]  version_dbg;

    minisoc_spi dut (
        .spi_sclk            (spi_sclk),
        .spi_cs_n            (spi_cs_n),
        .spi_mosi            (spi_mosi),
        .spi_miso            (spi_miso),
        .clk                 (clk),
        .rst_n               (rst_n),
        .status_busy         (status_busy),
        .status_done         (status_done),
        .status_error        (status_error),
        .status_blocks_done  (status_blocks_done),
        .pll_locked          (pll_locked),
        .cfg_key             (cfg_key),
        .cfg_iv              (cfg_iv),
        .cfg_counter         (cfg_counter),
        .cfg_num_blocks      (cfg_num_blocks),
        .cfg_mode            (cfg_mode),
        .cfg_decrypt         (cfg_decrypt),
        .cmd_start           (cmd_start),
        .version_dbg         (version_dbg)
    );

    // clk @ 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- Monitor de cmd_start --------------------------------------------
    integer cmd_start_pulses = 0;
    always @(posedge clk) if (cmd_start) cmd_start_pulses++;

    // ---- Helpers ---------------------------------------------------------
    integer errors = 0;
    task automatic check(input string msg, input logic cond);
        if (!cond) begin
            $display("FAIL: %s", msg);
            errors++;
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    // SPI frame send + MISO capture
    task automatic spi_send(input logic [39:0] frame, output logic [39:0] miso_cap);
        miso_cap = 40'h0;
        spi_cs_n = 1'b0;
        spi_mosi = frame[39];
        #(T_CS_SETUP);
        for (int i = 39; i >= 0; i--) begin
            spi_sclk = 1'b1;                    // rising: master samples MISO
            #1;
            miso_cap[i] = spi_miso;
            #(T_SCLK_HALF - 1);
            spi_sclk = 1'b0;                    // falling: slave shifts MISO
            if (i > 0) spi_mosi = frame[i-1];   // MOSI update for next bit
            #(T_SCLK_HALF);
        end
        #(T_CS_HOLD);
        spi_cs_n = 1'b1;
        #(T_CS_IDLE);
    endtask

    // Single-transaction write
    task automatic spi_write(input logic [5:0] addr, input logic [31:0] data);
        logic [39:0] dummy;
        spi_send({1'b0, addr, 1'b0, data}, dummy);
    endtask

    // Two-transaction read (read request + NOP phase)
    task automatic spi_read(input logic [5:0] addr, output logic [31:0] data);
        logic [39:0] dummy;
        logic [39:0] miso_nop;
        spi_send({1'b1, addr, 1'b0, 32'h0}, dummy);        // 1ª transação
        spi_send({1'b0, 6'h3F, 1'b0, 32'h0}, miso_nop);    // 2ª transação (NOP)
        data = miso_nop[31:0];
    endtask

    logic [31:0] rd;

    // ---- Testes ----------------------------------------------------------
    initial begin
        $fsdbDumpfile("spi_int.fsdb");
        $fsdbDumpvars(0, minisoc_spi_tb, "+all");

        spi_sclk           = 1'b0;
        spi_cs_n           = 1'b1;
        spi_mosi           = 1'b0;
        rst_n              = 1'b0;
        status_busy        = 1'b0;
        status_done        = 1'b0;
        status_error       = 1'b0;
        status_blocks_done = 9'd0;
        pll_locked         = 1'b0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // T1: write KEY0 via SPI, conferir cfg_key
        spi_write(6'h00, 32'hDEADBEEF);
        check("T1: cfg_key[127:96] = 0xDEADBEEF",
              cfg_key[127:96] == 32'hDEADBEEF);

        // T2: full KEY0 readback via SPI (RX + core + TX)
        spi_read(6'h00, rd);
        check("T2: KEY0 readback = 0xDEADBEEF", rd == 32'hDEADBEEF);

        // T3: write all 4 KEY words, conferir cfg_key completo
        spi_write(6'h01, 32'hCAFEBABE);
        spi_write(6'h02, 32'h12345678);
        spi_write(6'h03, 32'h87654321);
        check("T3: cfg_key completo",
              cfg_key == 128'hDEADBEEF_CAFEBABE_12345678_87654321);

        // T4: VERSION via SPI
        spi_read(6'h0D, rd);
        check("T4: VERSION read via SPI = 0x00000001", rd == 32'h00000001);

        // T5: version_dbg direto
        check("T5: version_dbg = 0x00000001", version_dbg == 32'h00000001);

        // T6: AES_CONTROL com START=1 -> cmd_start pulsa 1x
        // 0x0D = [4:2]=3 (CFB), [1]=0 (decrypt), [0]=1 (START)
        cmd_start_pulses = 0;
        spi_write(6'h0B, 32'h0D);
        #100;
        check("T6: cmd_start pulsou 1x", cmd_start_pulses == 1);
        check("T6: cfg_mode = 3", cfg_mode == 3'd3);
        check("T6: cfg_decrypt = 0", cfg_decrypt == 1'b0);

        // T7: AES_CONTROL com START=0 -> sem pulso
        // 0x06 = [4:2]=1 (CBC), [1]=1 (decrypt), [0]=0 (START)
        cmd_start_pulses = 0;
        spi_write(6'h0B, 32'h06);
        #100;
        check("T7: sem pulso de cmd_start", cmd_start_pulses == 0);
        check("T7: cfg_mode = 1", cfg_mode == 3'd1);
        check("T7: cfg_decrypt = 1", cfg_decrypt == 1'b1);

        // T8: AES_STATUS readback (status_busy e blocks_done)
        status_busy        = 1'b1;
        status_done        = 1'b0;
        status_error       = 1'b0;
        status_blocks_done = 9'd42;
        #50;
        spi_read(6'h0C, rd);
        check("T8: AES_STATUS.BUSY = 1", rd[0] == 1'b1);
        check("T8: AES_STATUS.BLOCKS_DONE = 42", rd[11:3] == 9'd42);

        // T9: SYSTEM_STATUS.PLL_LOCKED readback
        pll_locked = 1'b1;
        #50;
        spi_read(6'h0F, rd);
        check("T9: SYSTEM_STATUS.PLL_LOCKED = 1", rd[0] == 1'b1);

        // T10: MISO = 0 quando CS alto (idle)
        check("T10: MISO = 0 em CS idle", spi_miso == 1'b0);

        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #10_000_000;  // 10 ms guard
        $fatal(1, "TIMEOUT global");
    end

endmodule