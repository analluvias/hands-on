module tb_semana_02;

    int error_count = 0;

    // ------------------------------------------------------------------------
    // 1. Tabela de Referência Oficial da S-Box (FIPS-197, Figura 7)
    // ------------------------------------------------------------------------
    const logic [7:0] sbox_ref [0:255] = '{
        // 0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F
        8'h63, 8'h7c, 8'h77, 8'h7b ,8'hf2, 8'h6b, 8'h6f, 8'hc5, 8'h30, 8'h01, 8'h67, 8'h2b, 8'hfe, 8'hd7, 8'hab, 8'h76,//0
        8'hca, 8'h82, 8'hc9, 8'h7d, 8'hfa, 8'h59, 8'h47, 8'hf0, 8'had, 8'hd4, 8'ha2, 8'haf, 8'h9c, 8'ha4, 8'h72, 8'hc0, //1
        8'hb7, 8'hfd, 8'h93, 8'h26, 8'h36, 8'h3f, 8'hf7, 8'hcc, 8'h34, 8'ha5, 8'he5, 8'hf1, 8'h71, 8'hd8, 8'h31, 8'h15, //2
        8'h04, 8'hc7, 8'h23, 8'hc3, 8'h18, 8'h96, 8'h05, 8'h9a, 8'h07, 8'h12, 8'h80, 8'he2, 8'heb, 8'h27, 8'hb2, 8'h75, //3
        8'h09, 8'h83, 8'h2c, 8'h1a, 8'h1b, 8'h6e, 8'h5a, 8'ha0, 8'h52, 8'h3b, 8'hd6, 8'hb3, 8'h29, 8'he3, 8'h2f, 8'h84, //4
        8'h53, 8'hd1, 8'h00, 8'hed, 8'h20, 8'hfc, 8'hb1, 8'h5b, 8'h6a, 8'hcb, 8'hbe, 8'h39, 8'h4a, 8'h4c, 8'h58, 8'hcf, //5
        8'hd0, 8'hef, 8'haa, 8'hfb, 8'h43, 8'h4d, 8'h33, 8'h85, 8'h45, 8'hf9, 8'h02, 8'h7f, 8'h50, 8'h3c, 8'h9f, 8'ha8, //6
        // 0x70..0x7F (Linha 7)
        8'h51, 8'ha3, 8'h40, 8'h8f, 8'h92, 8'h9d, 8'h38, 8'hf5, 8'hbc, 8'hb6, 8'hda, 8'h21, 8'h10, 8'hff, 8'hf3, 8'hd2,

        // 0x80..0x8F (Linha 8)
        8'hcd, 8'h0c, 8'h13, 8'hec, 8'h5f, 8'h97, 8'h44, 8'h17, 8'hc4, 8'ha7, 8'h7e, 8'h3d, 8'h64, 8'h5d, 8'h19, 8'h73,

        // 0x90..0x9F (Linha 9)
        8'h60, 8'h81, 8'h4f, 8'hdc, 8'h22, 8'h2a, 8'h90, 8'h88, 8'h46, 8'hee, 8'hb8, 8'h14, 8'hde, 8'h5e, 8'h0b, 8'hdb,

        // 0xA0..0xAF (Linha A)
        8'he0, 8'h32, 8'h3a, 8'h0a, 8'h49, 8'h06, 8'h24, 8'h5c, 8'hc2, 8'hd3, 8'hac, 8'h62, 8'h91, 8'h95, 8'he4, 8'h79,

        // 0xB0..0xBF (Linha B)
        8'he7, 8'hc8, 8'h37, 8'h6d, 8'h8d, 8'hd5, 8'h4e, 8'ha9, 8'h6c, 8'h56, 8'hf4, 8'hea, 8'h65, 8'h7a, 8'hae, 8'h08,

        // 0xC0..0xCF (Linha C)
        8'hba, 8'h78, 8'h25, 8'h2e, 8'h1c, 8'ha6, 8'hb4, 8'hc6, 8'he8, 8'hdd, 8'h74, 8'h1f, 8'h4b, 8'hbd, 8'h8b, 8'h8a,

        // 0xD0..0xDF (Linha D)
        8'h70, 8'h3e, 8'hb5, 8'h66, 8'h48, 8'h03, 8'hf6, 8'h0e, 8'h61, 8'h35, 8'h57, 8'hb9, 8'h86, 8'hc1, 8'h1d, 8'h9e,

        // 0xE0..0xEF (Linha E)
        8'he1, 8'hf8, 8'h98, 8'h11, 8'h69, 8'hd9, 8'h8e, 8'h94, 8'h9b, 8'h1e, 8'h87, 8'he9, 8'hce, 8'h55, 8'h28, 8'hdf,

        // 0xF0..0xFF (Linha F)
        8'h8c, 8'ha1, 8'h89, 8'h0d, 8'hbf, 8'he6, 8'h42, 8'h68, 8'h41, 8'h99, 8'h2d, 8'h0f, 8'hb0, 8'h54, 8'hbb, 8'h16
    };

    // ------------------------------------------------------------------------
    // 2. Sinais para os DUTs
    // ------------------------------------------------------------------------
    logic [7:0]   sbox_in, sbox_out;
    logic [127:0] subbytes_in, subbytes_out;
    logic [127:0] shiftrows_in, shiftrows_out;

    // ------------------------------------------------------------------------
    // 3. Instanciação dos Módulos (DUTs)
    // ------------------------------------------------------------------------
    minisoc_aes_sbox u_sbox (
        .in (sbox_in),
        .out(sbox_out)
    );

    minisoc_aes_sub_bytes u_sub_bytes (
        .state_in (subbytes_in),
        .state_out(subbytes_out)
    );

    minisoc_aes_shift_rows u_shift_rows (
        .state_in (shiftrows_in),
        .state_out(shiftrows_out)
    );

    // ------------------------------------------------------------------------
    // 4. Sequência de Testes Autoverificável
    // ------------------------------------------------------------------------
    initial begin
        $display("==================================================");
        $display("  INICIANDO TESTBENCH - SEMANA 02 (MiniSoC AES)   ");
        $display("==================================================");

        // --------------------------------------------------------------------
        // TESTE 1: Varredura Completa da S-Box (0x00 a 0xFF)
        // --------------------------------------------------------------------
        $display("\n[1/3] Testando S-Box (256 entradas)...");
        for (int i = 0; i < 256; i++) begin
            sbox_in = i[7:0];
            #1; // Atraso para propagacao combinacional
            if (sbox_out !== sbox_ref[i]) begin
                $error("[ERRO S-Box] Entrada 0x%02X: Obtido 0x%02X, Esperado 0x%02X", 
                       sbox_in, sbox_out, sbox_ref[i]);
                error_count++;
            end
        end

        // Checagens pontuais específicas da especificação
        sbox_in = 8'h00; #1;
        assert (sbox_out == 8'h63) else begin
            $error("[ERRO S-Box] sbox(0x00) != 0x63"); error_count++;
        end

        sbox_in = 8'h53; #1;
        assert (sbox_out == 8'hed) else begin
            $error("[ERRO S-Box] sbox(0x53) != 0xed"); error_count++;
        end

        if (error_count == 0) $display("  -> S-Box: PASS (256/256 entradas verificadas com sucesso)");

        // --------------------------------------------------------------------
        // TESTE 2: Vetores FIPS-197 Apêndice B - Rodada 1
        // --------------------------------------------------------------------
        $display("\n[2/3] Testando Transformações da Rodada 1 (FIPS-197)...");

        // Vetores da Rodada 1
        subbytes_in = 128'h193de3bea0f4e22b9ac68d2ae9f84808; // Start of Round 1
        #1;

        assert (subbytes_out == 128'hd42711aee0bf98f1b8b45de51e415230)
            else begin
                $error("[ERRO SubBytes - Rodada 1]\n  Obtido  : %h\n  Esperado: d42711aee0bf98f1b8b45de51e415230", subbytes_out);
                error_count++;
            end

        shiftrows_in = subbytes_out; // Connection: After SubBytes -> ShiftRows
        #1;

        assert (shiftrows_out == 128'hd4bf5d30e0b452aeb84111f11e2798e5)
            else begin
                $error("[ERRO ShiftRows - Rodada 1]\n  Obtido  : %h\n  Esperado: d4bf5d30e0b452aeb84111f11e2798e5", shiftrows_out);
                error_count++;
            end

        if (error_count == 0) $display("  -> Rodada 1: PASS");

        // --------------------------------------------------------------------
        // TESTE 3: Vetores FIPS-197 Apêndice B - Rodada 10
        // --------------------------------------------------------------------
        $display("\n[3/3] Testando Transformações da Rodada 10 (FIPS-197)...");

        // Vetores da Rodada 10
        subbytes_in = 128'hbd6e7c3df2b5779e0b61216e8b10b689; // Start of Round 10
        #1;

        assert (subbytes_out == 128'h7a9f102789d5f50b2beffd9f3dca4ea7)
            else begin
                $error("[ERRO SubBytes - Rodada 10]\n  Obtido  : %h\n  Esperado: 7a9f102789d5f50b2beffd9f3dca4ea7", subbytes_out);
                error_count++;
            end

        shiftrows_in = subbytes_out;
        #1;

        assert (shiftrows_out == 128'h7ad5fda789ef4e272bca100b3d9ff59f)
            else begin
                $error("[ERRO ShiftRows - Rodada 10]\n  Obtido  : %h\n  Esperado: 7ad5fda789ef4e272bca100b3d9ff59f", shiftrows_out);
                error_count++;
            end

        if (error_count == 0) $display("  -> Rodada 10: PASS");

        // --------------------------------------------------------------------
        // RESUMO FINAL
        // --------------------------------------------------------------------
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("  STATUS FINAL: PASS - TODOS OS TESTES PASSARAM! ");
        end else begin
            $display("  STATUS FINAL: FAIL - %0d ERRO(S) ENCONTRADO(S)!", error_count);
        end
        $display("==================================================\n");

        $finish;
    end

endmodule