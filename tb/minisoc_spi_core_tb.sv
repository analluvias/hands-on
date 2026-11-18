`timescale 1ns/1ps

module minisoc_spi_core_tb;

    logic         clk;
    logic         rst_n;
    logic [39:0]  frame_data;
    logic         frame_valid_toggle;
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
    logic [31:0]  read_data;

    minisoc_spi_core dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .frame_data          (frame_data),
        .frame_valid_toggle  (frame_valid_toggle),
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
        .read_data           (read_data)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- Monitor de pulsos de cmd_start ------------------------------------
    integer cmd_start_pulses = 0;
    always @(posedge clk) if (cmd_start) cmd_start_pulses++;

    // ---- Helpers -----------------------------------------------------------
    integer errors = 0;
    task automatic check(input string msg, input logic cond);
        if (!cond) begin
            $display("FAIL: %s", msg);
            errors++;
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    task automatic send_write(input logic [5:0] addr, input logic [31:0] data);
        frame_data = {1'b0, addr, 1'b0, data};
        @(posedge clk);
        frame_valid_toggle = ~frame_valid_toggle;
        repeat (6) @(posedge clk);
    endtask

    task automatic send_read(input logic [5:0] addr);
        frame_data = {1'b1, addr, 1'b0, 32'd0};
        @(posedge clk);
        frame_valid_toggle = ~frame_valid_toggle;
        repeat (6) @(posedge clk);
    endtask

    // ---- Testes ------------------------------------------------------------
    initial begin
        $fsdbDumpfile("spi_core.fsdb");
        $fsdbDumpvars(0, minisoc_spi_core_tb, "+all");

        rst_n              = 1'b0;
        frame_data         = 40'd0;
        frame_valid_toggle = 1'b0;
        status_busy        = 1'b0;
        status_done        = 1'b0;
        status_error       = 1'b0;
        status_blocks_done = 9'd0;
        pll_locked         = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // T1: KEY0..3
        send_write(6'h00, 32'h11223344);
        send_write(6'h01, 32'h55667788);
        send_write(6'h02, 32'h99AABBCC);
        send_write(6'h03, 32'hDDEEFF00);
        check("T1: cfg_key", cfg_key == 128'h112233445566778899AABBCCDDEEFF00);

        // T2: IV0..3
        send_write(6'h04, 32'hAABBCCDD);
        send_write(6'h05, 32'hEEFF0011);
        send_write(6'h06, 32'h22334455);
        send_write(6'h07, 32'h66778899);
        check("T2: cfg_iv", cfg_iv == 128'hAABBCCDDEEFF00112233445566778899);

        // T3: COUNTER_HI/LO
        send_write(6'h08, 32'hDEADBEEF);
        send_write(6'h09, 32'hCAFEBABE);
        check("T3: cfg_counter", cfg_counter == 64'hDEADBEEFCAFEBABE);

        // T4: NUM_BLOCKS
        send_write(6'h0A, 32'd100);
        check("T4: cfg_num_blocks=100", cfg_num_blocks == 9'd100);
        send_write(6'h0A, 32'd256);
        check("T4b: cfg_num_blocks=256", cfg_num_blocks == 9'd256);

        // T5: AES_CONTROL (sem START) -> modo=5, decrypt=1
        //   bits: [4:2]=5=101, [1]=1, [0]=0  ->  32'h16
        send_write(6'h0B, 32'h16);
        check("T5: cfg_decrypt=1", cfg_decrypt == 1'b1);
        check("T5: cfg_mode=5",    cfg_mode    == 3'd5);

        // T6: START=1 escrito -> cmd_start pulsa 1x
        cmd_start_pulses = 0;
        send_write(6'h0B, 32'h17);
        check("T6: cmd_start pulsou 1x", cmd_start_pulses == 1);
        check("T6: cfg_mode mantido 5",  cfg_mode    == 3'd5);
        check("T6: cfg_decrypt mantido 1", cfg_decrypt == 1'b1);

        // T6b: START=0 escrito -> sem pulso
        cmd_start_pulses = 0;
        send_write(6'h0B, 32'h04);  // mode=1, decrypt=0, start=0
        check("T6b: sem pulso de cmd_start", cmd_start_pulses == 0);
        check("T6b: cfg_mode=1", cfg_mode == 3'd1);
        check("T6b: cfg_decrypt=0", cfg_decrypt == 1'b0);

        // T7: SYSTEM_CONTROL write -> read back
        //   MEM_SEL=1, PLL_EN=1, DIV=2: [3:2]=10, [1]=1, [0]=1  ->  32'h0B
        send_write(6'h0E, 32'h0B);
        send_read (6'h0E);
        check("T7: SYSTEM_CONTROL readback MEM_SEL_AES",
              read_data[0] == 1'b1);
        check("T7: SYSTEM_CONTROL readback PLL_ENABLE",
              read_data[1] == 1'b1);
        check("T7: SYSTEM_CONTROL readback PLL_DIV_SEL",
              read_data[3:2] == 2'b10);

        // T8: KEY readback
        send_read(6'h00);
        check("T8: read KEY0", read_data == 32'h11223344);
        send_read(6'h03);
        check("T8: read KEY3", read_data == 32'hDDEEFF00);
        send_read(6'h0A);
        check("T8: read NUM_BLOCKS", read_data == 32'd256);

        // T9: VERSION = 0x00000001
        send_read(6'h0D);
        check("T9: VERSION=0x00000001", read_data == 32'h0000_0001);

        // T10: write em VERSION nao altera
        send_write(6'h0D, 32'hDEADBEEF);
        send_read (6'h0D);
        check("T10: VERSION imutavel", read_data == 32'h0000_0001);

        // T11: AES_STATUS leitura
        status_busy        = 1'b1;
        status_done        = 1'b0;
        status_error       = 1'b0;
        status_blocks_done = 9'd42;
        send_read(6'h0C);
        check("T11: STATUS.BUSY",        read_data[0]     == 1'b1);
        check("T11: STATUS.DONE",        read_data[1]     == 1'b0);
        check("T11: STATUS.ERROR",       read_data[2]     == 1'b0);
        check("T11: STATUS.BLOCKS_DONE", read_data[11:3]  == 9'd42);

        // T12: SYSTEM_STATUS leitura (PLL_LOCKED)
        pll_locked = 1'b1;
        send_read(6'h0F);
        check("T12: SYSTEM_STATUS.PLL_LOCKED=1", read_data[0] == 1'b1);

        // T13: AES_STATUS eh RO
        status_busy        = 1'b0;
        status_done        = 1'b1;
        status_error       = 1'b1;
        status_blocks_done = 9'd7;
        send_write(6'h0C, 32'hFFFFFFFF);  // tentativa de write
        send_read (6'h0C);
        check("T13: STATUS.BUSY inalterado",        read_data[0]    == 1'b0);
        check("T13: STATUS.DONE inalterado",        read_data[1]    == 1'b1);
        check("T13: STATUS.ERROR inalterado",       read_data[2]    == 1'b1);
        check("T13: STATUS.BLOCKS_DONE inalterado", read_data[11:3] == 9'd7);

        // T14: SYSTEM_STATUS eh RO
        send_write(6'h0F, 32'hFFFFFFFF);
        send_read (6'h0F);
        check("T14: SYSTEM_STATUS.PLL_LOCKED inalterado", read_data[0] == 1'b1);

        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "TIMEOUT");
    end

endmodule