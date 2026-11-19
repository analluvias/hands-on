`timescale 1ns/1ps

module minisoc_spi_tb;

    // -------------------------------------------------------------------------
    // SPI master @ ~25 MHz (40 ns período, half-period 20 ns)
    // -------------------------------------------------------------------------
    localparam time T_SCLK_HALF = 20;
    localparam time T_CS_SETUP  = 20;
    localparam time T_CS_HOLD   = 20;
    localparam time T_CS_IDLE   = 100;

    // -------------------------------------------------------------------------
    // Sinais da interface externa
    // -------------------------------------------------------------------------
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

    logic         pll_enable_from_spi;
    logic [1:0]   pll_div_sel_from_spi;
    logic         mem_sel_aes_from_spi;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
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
        .version_dbg         (version_dbg),
        .pll_enable          (pll_enable_from_spi),
        .pll_div_sel         (pll_div_sel_from_spi),
        .mem_sel_aes         (mem_sel_aes_from_spi)
    );

    // -------------------------------------------------------------------------
    // PLL mock no mesmo top (fecha o loop PLL_ENABLE -> pll_locked)
    // -------------------------------------------------------------------------
    logic pll_sys_clk_unused;
    minisoc_pll_mock #(.LOCK_CYCLES(16)) u_pll (
        .clk         (clk),
        .rst_n       (rst_n),
        .pll_enable  (pll_enable_from_spi),
        .pll_div_sel (pll_div_sel_from_spi),
        .pll_locked  (pll_locked),
        .sys_clk     (pll_sys_clk_unused)
    );

    // -------------------------------------------------------------------------
    // clk @ 2 GHz (500 ps período, 250 ps half-period)
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always #250 clk = ~clk;

    // -------------------------------------------------------------------------
    // Monitor de cmd_start
    // -------------------------------------------------------------------------
    integer cmd_start_pulses = 0;
    always @(posedge clk) if (cmd_start) cmd_start_pulses++;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    integer errors = 0;

    task automatic check(input string msg, input logic cond);
        if (!cond) begin
            $display("FAIL: %s", msg);
            errors++;
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    // Envia 1 frame SPI de 40 bits, captura MISO
    task automatic spi_send(input logic [39:0] frame, output logic [39:0] miso_cap);
        miso_cap = 40'h0;
        spi_cs_n = 1'b0;
        spi_mosi = frame[39];
        #(T_CS_SETUP);
        for (int i = 39; i >= 0; i--) begin
            spi_sclk = 1'b1;
            #1;
            miso_cap[i] = spi_miso;
            #(T_SCLK_HALF - 1);
            spi_sclk = 1'b0;
            if (i > 0) spi_mosi = frame[i-1];
            #(T_SCLK_HALF);
        end
        #(T_CS_HOLD);
        spi_cs_n = 1'b1;
        #(T_CS_IDLE);
    endtask

    task automatic spi_write(input logic [5:0] addr, input logic [31:0] data);
        logic [39:0] dummy;
        spi_send({1'b0, addr, 1'b0, data}, dummy);
    endtask

    task automatic spi_read(input logic [5:0] addr, output logic [31:0] data);
        logic [39:0] dummy;
        logic [39:0] miso_nop;
        spi_send({1'b1, addr, 1'b0, 32'h0}, dummy);       // 1ª: read request
        spi_send({1'b0, 6'h3F, 1'b0, 32'h0}, miso_nop);   // 2ª: NOP, captura MISO
        data = miso_nop[31:0];
    endtask

    // Variáveis de trabalho
    logic [31:0] rd;
    logic [31:0] expected;
    logic [31:0] patterns [3] = '{32'h0000_0000, 32'hFFFF_FFFF, 32'hA5A5_A5A5};

    // Registers R/W genéricos (sem masks, sem side-effects)
    logic [5:0] rw_regs [12] = '{
        6'h00, 6'h01, 6'h02, 6'h03,  // KEY0..KEY3
        6'h04, 6'h05, 6'h06, 6'h07,  // IV0..IV3
        6'h08, 6'h09,                // COUNTER_HI/LO
        6'h0A,                       // NUM_BLOCKS (mas truncado, tratado depois)
        6'h0B                       // AES_CONTROL (mas com W1P, tratado depois)
    };

    // -------------------------------------------------------------------------
    // Sequência de testes
    // -------------------------------------------------------------------------
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

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // =====================================================================
        // T1: Round-trip de KEY0..3 e IV0..3 com 3 padrões
        // =====================================================================
        for (int r = 0; r < 8; r++) begin
            for (int p = 0; p < 3; p++) begin
                spi_write(rw_regs[r], patterns[p]);
                spi_read (rw_regs[r], rd);
                $display("T1: reg=0x%02h pat=0x%08h rd=0x%08h",
                         rw_regs[r], patterns[p], rd);
                check("T1 round-trip",
                      rd == patterns[p]);
            end
        end
        // Estado final após T1 (último padrão = 0xA5A5A5A5)
        check("T1: cfg_key final = 0xA5A5A5A5*4",
              cfg_key == 128'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5);
        check("T1: cfg_iv final = 0xA5A5A5A5*4",
              cfg_iv == 128'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5);

        // =====================================================================
        // T2: COUNTER_HI/LO com 3 padrões + check cfg_counter final
        // =====================================================================
        for (int p = 0; p < 3; p++) begin
            spi_write(6'h08, patterns[p]);  // HI
            spi_write(6'h09, ~patterns[p]); // LO (para diferenciar)
            spi_read (6'h08, rd);
            check("T2: COUNTER_HI round-trip", rd == patterns[p]);
            spi_read (6'h09, rd);
            check("T2: COUNTER_LO round-trip", rd == ~patterns[p]);
        end
        // Estado final: HI=0xA5A5A5A5, LO=~0xA5A5A5A5=0x5A5A5A5A
        check("T2: cfg_counter final",
              cfg_counter == 64'hA5A5_A5A5_5A5A_5A5A);

        // =====================================================================
        // T3: NUM_BLOCKS (mask 0x1FF)
        // =====================================================================
        for (int p = 0; p < 3; p++) begin
            spi_write(6'h0A, patterns[p]);
            spi_read (6'h0A, rd);
            expected = {23'd0, patterns[p][8:0]};
            $display("T3: pat=0x%08h expected=0x%08h rd=0x%08h",
                     patterns[p], expected, rd);
            check("T3: NUM_BLOCKS masked round-trip", rd == expected);
            check("T3: cfg_num_blocks propagation",
                  cfg_num_blocks == patterns[p][8:0]);
        end

        // =====================================================================
        // T4: AES_CONTROL (mask; START não armazena, W1P)
        // =====================================================================
        for (int p = 0; p < 3; p++) begin
            cmd_start_pulses = 0;
            spi_write(6'h0B, patterns[p]);
            #100;
            spi_read(6'h0B, rd);
            expected = {27'd0, patterns[p][4:2], patterns[p][1], 1'b0};
            $display("T4: pat=0x%08h expected=0x%08h rd=0x%08h pulses=%0d",
                     patterns[p], expected, rd, cmd_start_pulses);
            check("T4: AES_CONTROL masked round-trip", rd == expected);
            check("T4: cfg_mode propagation",
                  cfg_mode == patterns[p][4:2]);
            check("T4: cfg_decrypt propagation",
                  cfg_decrypt == patterns[p][1]);
            check("T4: cmd_start pulse iff START=1",
                  cmd_start_pulses == {31'd0, patterns[p][0]});
        end

        // =====================================================================
        // T5: Read-only imutabilidade (AES_STATUS, VERSION, SYSTEM_STATUS)
        // =====================================================================
        // Congela os inputs do AES_STATUS; PLL está desabilitado (reset)
        status_busy        = 1'b0;
        status_done        = 1'b0;
        status_error       = 1'b0;
        status_blocks_done = 9'd0;
        #100;
        check("T5: pll_locked=0 antes do teste RO", pll_locked == 1'b0);

        // Captura estado inicial
        logic [31:0] aes_status_init;
        logic [31:0] version_init;
        logic [31:0] sys_status_init;
        spi_read(6'h0C, aes_status_init);
        spi_read(6'h0D, version_init);
        spi_read(6'h0F, sys_status_init);
        $display("T5: init AES_STATUS=0x%08h VERSION=0x%08h SYS_STATUS=0x%08h",
                 aes_status_init, version_init, sys_status_init);
        check("T5: VERSION init = 0x00000001", version_init == 32'h00000001);

        // Tenta escrever e verifica imutabilidade
        for (int p = 0; p < 3; p++) begin
            spi_write(6'h0C, patterns[p]);
            spi_write(6'h0D, patterns[p]);
            spi_write(6'h0F, patterns[p]);
            spi_read (6'h0C, rd);
            check("T5: AES_STATUS imutável", rd == aes_status_init);
            spi_read (6'h0D, rd);
            check("T5: VERSION imutável", rd == version_init);
            spi_read (6'h0F, rd);
            check("T5: SYSTEM_STATUS imutável", rd == sys_status_init);
        end

        // =====================================================================
        // T6: PLL enable + lock nos 4 divisores (loop fechado com PLL mock)
        // =====================================================================
        for (int div = 0; div < 4; div++) begin
            // Estado limpo: PLL desabilitado
            spi_write(6'h0E, {28'd0, div[1:0], 1'b0, 1'b0});  // PLL_ENABLE=0
            #100;
            check("T6: pll_locked=0 após disable",
                  pll_locked == 1'b0);

            // Habilita PLL com divisor
            spi_write(6'h0E, {28'd0, div[1:0], 1'b1, 1'b0});  // PLL_ENABLE=1
            check("T6: pll_enable output",   pll_enable_from_spi  == 1'b1);
            check("T6: pll_div_sel output",  pll_div_sel_from_spi == div[1:0]);

            // Aguarda lock (com timeout local)
            fork : wait_lock
                wait (pll_locked);
                begin
                    #1_000_000;  // 1 µs de folga
                    $fatal(1, "TIMEOUT: PLL não lockou (div=%0d)", div);
                end
            join_any
            disable wait_lock;

            // Confirma via SPI read de SYSTEM_STATUS
            spi_read(6'h0F, rd);
            $display("T6: div=%0d SYS_STATUS=0x%08h pll_locked=%0b",
                     div, rd, pll_locked);
            check("T6: SYSTEM_STATUS.PLL_LOCKED via SPI",
                  rd[0] == 1'b1);

            // Desabilita antes do próximo divisor
            spi_write(6'h0E, {28'd0, div[1:0], 1'b0, 1'b0});
            #100;
        end

        // Restaura PLL disabled
        spi_write(6'h0E, 32'h0);
        #100;
        check("T6: PLL desabilitado no fim", pll_locked == 1'b0);

        // =====================================================================
        // T7: MISO idle quando CS=1
        // =====================================================================
        check("T7: MISO = 0 em CS idle", spi_miso == 1'b0);

        // =====================================================================
        // Resultado
        // =====================================================================
        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #100_000_000;  // 100 ms guard
        $fatal(1, "TIMEOUT global");
    end

endmodule