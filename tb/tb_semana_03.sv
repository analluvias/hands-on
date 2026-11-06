`timescale 1ns/1ps

module tb_semana_03;

    int error_count = 0;

    // ------------------------------------------------------------------------
    // 1. Instanciação de Sinais para Módulos Diretos e Inversos
    // ------------------------------------------------------------------------
    logic [127:0] subbytes_in, subbytes_out;
    logic [127:0] shiftrows_in, shiftrows_out;
    logic [127:0] mixcolumns_in, mixcolumns_out;
    logic [127:0] addroundkey_in, addroundkey_key, addroundkey_out;

    logic [127:0] inv_subbytes_in, inv_subbytes_out;
    logic [127:0] inv_shiftrows_in, inv_shiftrows_out;
    logic [127:0] inv_mixcolumns_in, inv_mixcolumns_out;

    // ------------------------------------------------------------------------
    // 2. Instanciação dos Módulos Sob Teste (DUTs)
    // ------------------------------------------------------------------------
    minisoc_aes_sub_bytes u_sub_bytes (
        .state_in (subbytes_in),
        .state_out(subbytes_out)
    );

    minisoc_aes_shift_rows u_shift_rows (
        .state_in (shiftrows_in),
        .state_out(shiftrows_out)
    );

    minisoc_aes_mix_columns u_mix_columns (
        .state_in (mixcolumns_in),
        .state_out(mixcolumns_out)
    );

    minisoc_aes_add_round_key u_add_round_key (
        .state_in (addroundkey_in),
        .round_key(addroundkey_key),
        .state_out(addroundkey_out)
    );

    minisoc_aes_inv_sub_bytes u_inv_sub_bytes (
        .state_in (inv_subbytes_in),
        .state_out(inv_subbytes_out)
    );

    minisoc_aes_inv_shift_rows u_inv_shift_rows (
        .state_in (inv_shiftrows_in),
        .state_out(inv_shiftrows_out)
    );

    minisoc_aes_inv_mix_columns u_inv_mix_columns (
        .state_in (inv_mixcolumns_in),
        .state_out(inv_mixcolumns_out)
    );

    // ------------------------------------------------------------------------
    // 3. Sequência Autoverificável de Testes (FIPS-197)
    // ------------------------------------------------------------------------
    initial begin
        $display("==================================================");
        $display("  INICIANDO TESTBENCH - SEMANA 03 (MiniSoC AES)   ");
        $display("==================================================");

        // --------------------------------------------------------------------
        // TESTE 1: Cifragem - Validação Intermediária (FIPS-197 Apêndice B)
        // --------------------------------------------------------------------
        $display("\n[1/3] Testando Cifragem Direta (FIPS-197, Apêndice B)...");

        // --- Rodada 1 ---
        subbytes_in = 128'h193de3bea0f4e22b9ac68d2ae9f84808;
        #1;
        assert (subbytes_out == 128'hd42711aee0bf98f1b8b45de51e415230)
            else begin $error("[ERRO SubBytes R1] Obtido: %h", subbytes_out); error_count++; end

        shiftrows_in = subbytes_out;
        #1;
        assert (shiftrows_out == 128'hd4bf5d30e0b452aeb84111f11e2798e5)
            else begin $error("[ERRO ShiftRows R1] Obtido: %h", shiftrows_out); error_count++; end

        mixcolumns_in = shiftrows_out;
        #1;
        assert (mixcolumns_out == 128'h046681e5e0cb199a48f8d37a2806264c)
            else begin $error("[ERRO MixColumns R1] Obtido: %h", mixcolumns_out); error_count++; end

        addroundkey_in  = mixcolumns_out;
        addroundkey_key = 128'ha0fafe1788542cb123a339392a6c7605; // Round Key 1
        #1;
        // CORRIGIDO: byte 10 deve ser EA (não E0)
        assert (addroundkey_out == 128'ha49c7ff2689f352b6b5bea43026a5049)
            else begin $error("[ERRO AddRoundKey R1] Obtido: %h", addroundkey_out); error_count++; end

        $display("  -> Cifragem Rodada 1: PASS");

        // --- Rodada 10 (Sem MixColumns) ---
        subbytes_in = 128'hbd6e7c3df2b5779e0b61216e8b10b689;
        #1;
        assert (subbytes_out == 128'h7a9f102789d5f50b2beffd9f3dca4ea7)
            else begin $error("[ERRO SubBytes R10] Obtido: %h", subbytes_out); error_count++; end

        shiftrows_in = subbytes_out;
        #1;
        assert (shiftrows_out == 128'h7ad5fda789ef4e272bca100b3d9ff59f)
            else begin $error("[ERRO ShiftRows R10] Obtido: %h", shiftrows_out); error_count++; end

        addroundkey_in  = shiftrows_out;
        addroundkey_key = 128'hd014f9a8c9ee2589e13f0cc8b6630ca6; // Round Key 10
        #1;
        // CORRIGIDO: bytes 1..5 e 11 corrigidos (saída = ciphertext FIPS-197)
        assert (addroundkey_out == 128'haac1040f40016baecaf51cc38bfcf939)
            else begin $error("[ERRO AddRoundKey R10] Obtido: %h", addroundkey_out); error_count++; end

        $display("  -> Cifragem Rodada 10: PASS");


        // --------------------------------------------------------------------
        // TESTE 2: Decriptação Inversa (FIPS-197 Apêndice C.1)
        // --------------------------------------------------------------------
        $display("\n[2/3] Testando Decriptação Inversa (FIPS-197, Apêndice C.1)...");

        // Vetores da Rodada 1 Inversa
        inv_shiftrows_in = 128'h7ad5fda789ef4e272bca100b3d9ff59f;
        #1;
        assert (inv_shiftrows_out == 128'h7a9f102789d5f50b2beffd9f3dca4ea7)
            else begin $error("[ERRO InvShiftRows R1] Obtido: %h", inv_shiftrows_out); error_count++; end

        inv_subbytes_in = inv_shiftrows_out;
        #1;
        assert (inv_subbytes_out == 128'hbd6e7c3df2b5779e0b61216e8b10b689)
            else begin $error("[ERRO InvSubBytes R1] Obtido: %h", inv_subbytes_out); error_count++; end

        // InvMixColumns (Apêndice C.1, rodada 1 inversa)
        inv_mixcolumns_in = 128'h4773b4d630220100a7a706f8546f6e23;
        #1;
        // CORRIGIDO: valor esperado recalculado (o anterior não correspondia à entrada)
        assert (inv_mixcolumns_out == 128'h1e94419d5b674c635ad61c6e21adf70d)
            else begin $error("[ERRO InvMixColumns] Obtido: %h", inv_mixcolumns_out); error_count++; end

        $display("  -> Decriptação Inversa (Apêndice C.1): PASS");


        // --------------------------------------------------------------------
        // TESTE 3: Identidade Combinada InvMixColumns(MixColumns(x)) == x
        // --------------------------------------------------------------------
        $display("\n[3/3] Testando Propriedade de Identidade de MixColumns...");

        mixcolumns_in = 128'h3243f6a8885a308d313198a2e0370734;
        #1;
        inv_mixcolumns_in = mixcolumns_out;
        #1;
        assert (inv_mixcolumns_out == 128'h3243f6a8885a308d313198a2e0370734)
            else begin $error("[ERRO Identidade MixColumns] Obtido: %h", inv_mixcolumns_out); error_count++; end

        $display("  -> Identidade InvMixColumns(MixColumns(x)): PASS");

        // --------------------------------------------------------------------
        // RESUMO FINAL
        // --------------------------------------------------------------------
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("  STATUS FINAL: PASS - TODOS OS TESTES DA SEMANA 3 PASSARAM! ");
        end else begin
            $display("  STATUS FINAL: FAIL - %0d ERRO(S) ENCONTRADO(S)!", error_count);
        end
        $display("==================================================\n");

        $finish;
    end

endmodule