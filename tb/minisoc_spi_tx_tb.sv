`timescale 1ns/1ps

module minisoc_spi_tx_tb;

    // SPI master @ ~25 MHz (40 ns período)
    localparam time T_SCLK_HALF = 20;
    localparam time T_CS_SETUP  = 20;
    localparam time T_CS_HOLD   = 20;
    localparam time T_CS_IDLE   = 100;

    logic        spi_sclk;
    logic        spi_cs_n;
    logic        rst_n;
    logic [31:0] read_data;
    logic        spi_miso;

    minisoc_spi_tx dut (
        .spi_sclk  (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .rst_n     (rst_n),
        .read_data (read_data),
        .spi_miso  (spi_miso)
    );

    // ---- Helpers ----------------------------------------------------------
    integer errors = 0;
    task automatic check(input string msg, input logic cond);
        if (!cond) begin
            $display("FAIL: %s", msg);
            errors++;
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    // ---- SPI master: 1 frame de 40 bits, captura MISO ----------------------
    task automatic spi_frame(output logic [39:0] miso_out);
        miso_out = 40'h0;
        spi_cs_n = 1'b0;
        #(T_CS_SETUP);
        for (int i = 39; i >= 0; i--) begin
            spi_sclk = 1'b1;              // rising edge (master amostra MISO)
            #1;
            miso_out[i] = spi_miso;
            #(T_SCLK_HALF - 1);
            spi_sclk = 1'b0;              // falling edge (DUT desloca)
            #(T_SCLK_HALF);
        end
        #(T_CS_HOLD);
        spi_cs_n = 1'b1;
        #(T_CS_IDLE);
    endtask

    // ---- Testes -----------------------------------------------------------
    logic [39:0] miso;

    initial begin
        $fsdbDumpfile("spi_tx.fsdb");
        $fsdbDumpvars(0, minisoc_spi_tx_tb, "+all");

        spi_sclk  = 1'b0;
        spi_cs_n  = 1'b1;
        rst_n     = 1'b0;
        read_data = 32'h0;

        repeat (5) #10;
        rst_n = 1'b1;
        #50;

        // T1: read_data=0 -> MISO envia 8 zeros + 32 zeros
        read_data = 32'h00000000;
        #50;
        spi_frame(miso);
        check("T1: MISO = {8'h00, 0x00000000}",
              miso == 40'h00_00000000);

        // T2: read_data=0xDEADBEEF
        read_data = 32'hDEADBEEF;
        #50;
        spi_frame(miso);
        check("T2: MISO = {8'h00, 0xDEADBEEF}",
              miso == 40'h00_DEADBEEF);

        // T3: read_data=0xFFFFFFFF
        read_data = 32'hFFFFFFFF;
        #50;
        spi_frame(miso);
        check("T3: MISO = {8'h00, 0xFFFFFFFF}",
              miso == 40'h00_FFFFFFFF);

        // T4: read_data=0x12345678
        read_data = 32'h12345678;
        #50;
        spi_frame(miso);
        check("T4: MISO = {8'h00, 0x12345678}",
              miso == 40'h00_12345678);

        // T5: read_data muda entre frames -> MISO reflete o novo valor
        read_data = 32'hA5A5A5A5;
        #50;
        spi_frame(miso);
        check("T5: MISO = {8'h00, 0xA5A5A5A5}",
              miso == 40'h00_A5A5A5A5);

        // T6: MISO = 0 quando CS alto (idle)
        check("T6: MISO = 0 quando CS=1", spi_miso == 1'b0);

        // T7: frame curto de 16 bits (CS sobe antes do fim) — só verifica que
        // MISO não trava em X; o protocolo exige 40 bits, isto é só sanidade
        read_data = 32'hCAFEBABE;
        #50;
        begin
            logic [15:0] partial;
            spi_cs_n = 1'b0;
            #(T_CS_SETUP);
            for (int i = 15; i >= 0; i--) begin
                spi_sclk = 1'b1;
                #1;
                partial[i] = spi_miso;
                #(T_SCLK_HALF - 1);
                spi_sclk = 1'b0;
                #(T_SCLK_HALF);
            end
            #(T_CS_HOLD);
            spi_cs_n = 1'b1;
            #(T_CS_IDLE);
            check("T7: MISO high-Z ou 0 em abort (sem X)",
                  spi_miso === 1'b0);
        end

        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "TIMEOUT");
    end

endmodule