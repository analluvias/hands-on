`timescale 1ns/1ps

module minisoc_spi_rx_tb;

    // SPI Mode 0 @ ~25 MHz (40 ns período)
    localparam int T_SCLK_HALF = 20;
    localparam int T_CS_SETUP  = 10;
    localparam int T_CS_HOLD   = 10;
    localparam int T_CS_IDLE   = 50;

    logic        spi_sclk;
    logic        spi_cs_n;
    logic        spi_mosi;
    logic        rst_n;
    logic [39:0] frame_data;
    logic        frame_valid_toggle;

    minisoc_spi_rx dut (
        .spi_sclk           (spi_sclk),
        .spi_cs_n           (spi_cs_n),
        .spi_mosi           (spi_mosi),
        .rst_n              (rst_n),
        .frame_data         (frame_data),
        .frame_valid_toggle (frame_valid_toggle)
    );

    // -------------------------------------------------------------------------
    // Monitor de edges do toggle
    // -------------------------------------------------------------------------
    integer toggle_edges = 0;
    logic   toggle_prev  = 1'b0;

    always @(frame_valid_toggle) begin
        if (!$isunknown(frame_valid_toggle) &&
            !$isunknown(toggle_prev) &&
            (frame_valid_toggle !== toggle_prev))
            toggle_edges++;
        if (!$isunknown(frame_valid_toggle))
            toggle_prev = frame_valid_toggle;
    end

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

    // -------------------------------------------------------------------------
    // SPI master model (Mode 0, MSB-first)
    // -------------------------------------------------------------------------
    task automatic spi_send_frame(input logic [39:0] frame);
        spi_cs_n = 1'b0;
        #(T_CS_SETUP);
        for (integer i = 39; i >= 0; i--) begin
            spi_mosi = frame[i];
            #(T_SCLK_HALF);
            spi_sclk = 1'b1;   // DUT amostra aqui (rising edge)
            #(T_SCLK_HALF);
            spi_sclk = 1'b0;
        end
        #(T_CS_HOLD);
        spi_cs_n = 1'b1;       // dispara async reset de bit_cnt/shift_reg
        #(T_CS_IDLE);
    endtask

    logic toggle_before;

    // -------------------------------------------------------------------------
    // Testes
    // -------------------------------------------------------------------------
    initial begin
        $fsdbDumpfile("spi_rx.fsdb");
        $fsdbDumpvars(0, minisoc_spi_rx_tb, "+all");

        spi_sclk = 1'b0;
        spi_cs_n = 1'b1;
        spi_mosi = 1'b0;
        rst_n    = 1'b0;

        repeat (5) #10;
        rst_n = 1'b1;
        #50;

        // T1: estado inicial pós-reset
        check("T1: frame_valid_toggle=0 após reset",
              frame_valid_toggle == 1'b0);
        check("T1: frame_data=0 após reset",
              frame_data == 40'd0);
        check("T1: toggle_edges=0",
              toggle_edges == 0);

        // T2: frame completo, todos zeros
        spi_send_frame(40'h0000000000);
        check("T2: frame_data=0x0000000000",
              frame_data == 40'h0000000000);
        check("T2: toggle=1 após 1º frame",
              frame_valid_toggle == 1'b1);
        check("T2: toggle_edges=1",
              toggle_edges == 1);

        // T3: frame completo, todos uns (RSV mascarado para 0)
        //   Original: F F F F F F F F F F (10 nibbles)
        //   Bit 32 é o LSB do nibble[8] (2º da esquerda):
        //     F -> E. Resultado: FE_FF_FF_FF_FF = 0xFE_FFFFFFFF... 
        //   Como 40-bit = 10 nibbles: 0xFEFFFFFFFF
        spi_send_frame(40'hFFFFFFFFFF);
        check("T3: frame_data=0xFEFFFFFFFF (RSV mask)",
              frame_data == 40'hFEFFFFFFFF);
        check("T3: toggle=0 após 2º frame",
              frame_valid_toggle == 1'b0);
        check("T3: toggle_edges=2",
              toggle_edges == 2);

        // T4: pattern específico com RSV=0 (mask não altera)
        //   0x0A5A3C12F4 -> RWb=0, ADDR=0x0A, RSV=0, DATA=0x5A3C12F4
        spi_send_frame(40'h0A5A3C12F4);
        check("T4: frame_data=0x0A5A3C12F4",
              frame_data == 40'h0A5A3C12F4);

        // T5: RSV=1 é mascarado para 0
        //   0xFF000000FF -> RWb=1, ADDR=0x3F, RSV=1, DATA=0x000000FF
        //   Mascarando RSV: RWb=1, ADDR=0x3F, RSV=0, DATA=0x000000FF
        //   = 0xFE000000FF
        spi_send_frame(40'hFF000000FF);
        check("T5: frame_data=0xFE000000FF (RSV mask)",
              frame_data == 40'hFE000000FF);
        check("T5: toggle_edges=4",
              toggle_edges == 4);

        // T6: abort no meio do frame, toggle NÃO dispara
        toggle_before = frame_valid_toggle;
        toggle_edges  = 0;

        spi_cs_n = 1'b0;
        #(T_CS_SETUP);
        for (integer i = 39; i >= 20; i--) begin   // apenas 20 bits
            spi_mosi = 1'b1;
            #(T_SCLK_HALF);
            spi_sclk = 1'b1;
            #(T_SCLK_HALF);
            spi_sclk = 1'b0;
        end
        spi_cs_n = 1'b1;   // aborta
        #(T_CS_IDLE);

        check("T6: toggle não disparou em frame abortado",
              frame_valid_toggle == toggle_before);
        check("T6: toggle_edges=0 em abort",
              toggle_edges == 0);

        // T7: frame completo após abort (CS recovery)
        spi_send_frame(40'h123456789A);
        check("T7: frame_data=0x123456789A após abort+frame",
              frame_data == 40'h123456789A);

        // Resultado
        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #1_000_000;  // 1 ms guard
        $fatal(1, "TIMEOUT");
    end

endmodule