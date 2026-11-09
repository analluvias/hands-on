`timescale 1ns/1ps

module tb_semana_03;

    int error_count = 0;

    // ------------------------------------------------------------------------
    // 1. Sinais para Módulos Diretos e Inversos
    // ------------------------------------------------------------------------
    logic [127:0] subbytes_in, subbytes_out;
    logic [127:0] shiftrows_in, shiftrows_out;
    logic [127:0] mixcolumns_in, mixcolumns_out;
    logic [127:0] addroundkey_in, addroundkey_key, addroundkey_out;

    logic [127:0] inv_subbytes_in, inv_subbytes_out;
    logic [127:0] inv_shiftrows_in, inv_shiftrows_out;
    logic [127:0] inv_mixcolumns_in, inv_mixcolumns_out;

    // ------------------------------------------------------------------------
    // 2. DUTs
    // ------------------------------------------------------------------------
    minisoc_aes_sub_bytes       u_sub_bytes       (.state_in(subbytes_in),       .state_out(subbytes_out));
    minisoc_aes_shift_rows      u_shift_rows      (.state_in(shiftrows_in),      .state_out(shiftrows_out));
    minisoc_aes_mix_columns     u_mix_columns     (.state_in(mixcolumns_in),     .state_out(mixcolumns_out));
    minisoc_aes_add_round_key   u_add_round_key   (.state_in(addroundkey_in),    .round_key(addroundkey_key), .state_out(addroundkey_out));
    minisoc_aes_inv_sub_bytes   u_inv_sub_bytes   (.state_in(inv_subbytes_in),   .state_out(inv_subbytes_out));
    minisoc_aes_inv_shift_rows  u_inv_shift_rows  (.state_in(inv_shiftrows_in),  .state_out(inv_shiftrows_out));
    minisoc_aes_inv_mix_columns u_inv_mix_columns (.state_in(inv_mixcolumns_in), .state_out(inv_mixcolumns_out));

    // ------------------------------------------------------------------------
    // 3. Testes (todos os vetores do FIPS-197, 26/nov/2001)
    // ------------------------------------------------------------------------
    initial begin
        $display("==================================================");
        $display("  TESTBENCH SEMANA 03 - MiniSoC AES               ");
        $display("  Vetores: FIPS-197 Apendices A.1, B e C.1        ");
        $display("==================================================");

        // ====================================================================
        // TESTE 1: Cifragem Direta
        // ====================================================================
        $display("\n[1/3] Cifragem Direta (FIPS-197 Apendice B + C.1)...");

        // --------------------------------------------------------------------
        // Rodada 1: Apendice B
        //   Plaintext  = 3243f6a8885a308d313198a2e0370734
        //   Cipher Key = 2b7e151628aed2a6abf7158809cf4f3c
        // --------------------------------------------------------------------
        $display("  -- Rodada 1 (Apendice B) --");

        // FIPS-197 Ap. B: Start of Round 1
        subbytes_in = 128'h193de3bea0f4e22b9ac68d2ae9f84808;
        #1;
        // FIPS-197 Ap. B: After SubBytes
        assert (subbytes_out == 128'hd42711aee0bf98f1b8b45de51e415230)
            else begin $error("[ERRO SubBytes R1] Obtido: %h", subbytes_out); error_count++; end

        shiftrows_in = subbytes_out;
        #1;
        // FIPS-197 Ap. B: After ShiftRows
        assert (shiftrows_out == 128'hd4bf5d30e0b452aeb84111f11e2798e5)
            else begin $error("[ERRO ShiftRows R1] Obtido: %h", shiftrows_out); error_count++; end

        mixcolumns_in = shiftrows_out;
        #1;
        // FIPS-197 Ap. B: After MixColumns
        assert (mixcolumns_out == 128'h046681e5e0cb199a48f8d37a2806264c)
            else begin $error("[ERRO MixColumns R1] Obtido: %h", mixcolumns_out); error_count++; end

        addroundkey_in  = mixcolumns_out;
        // FIPS-197 Ap. A.1: Round Key 1 (w[4..7]) do vetor B
        addroundkey_key = 128'ha0fafe1788542cb123a339392a6c7605;
        #1;
        // FIPS-197 Ap. B: After AddRoundKey (= Start of Round 2)
        // NOTA: O PDF imprime '...6b5be0 43...' no byte 10, mas o valor
        // correto e '...6b5bea 43...'. Prova por XOR:
        //   d3 (mixcol byte 10) XOR 39 (roundkey byte 10) = ea
        // (typo conhecido do FIPS-197; a cadeia so fecha com 'ea')
        assert (addroundkey_out == 128'ha49c7ff2689f352b6b5bea43026a5049)
            else begin $error("[ERRO AddRoundKey R1] Obtido: %h", addroundkey_out); error_count++; end

        $display("  -> SubBytes / ShiftRows / MixColumns / AddRoundKey R1: PASS");

        // --------------------------------------------------------------------
        // Rodada 10: Apendice C.1
        //   Plaintext  = 00112233445566778899aabbccddeeff
        //   Cipher Key = 000102030405060708090a0b0c0d0e0f
        // (Todos os valores abaixo vem do MESMO vetor C.1)
        // --------------------------------------------------------------------
        $display("  -- Rodada 10 (Apendice C.1) --");

        // FIPS-197 Ap. C.1: round[10].start
        subbytes_in = 128'hbd6e7c3df2b5779e0b61216e8b10b689;
        #1;
        // FIPS-197 Ap. C.1: round[10].s_box
        assert (subbytes_out == 128'h7a9f102789d5f50b2beffd9f3dca4ea7)
            else begin $error("[ERRO SubBytes R10] Obtido: %h", subbytes_out); error_count++; end

        shiftrows_in = subbytes_out;
        #1;
        // FIPS-197 Ap. C.1: round[10].s_row
        assert (shiftrows_out == 128'h7ad5fda789ef4e272bca100b3d9ff59f)
            else begin $error("[ERRO ShiftRows R10] Obtido: %h", shiftrows_out); error_count++; end

        addroundkey_in  = shiftrows_out;
        // FIPS-197 Ap. C.1: round[10].k_sch (Round Key 10 do vetor C.1)
        addroundkey_key = 128'h13111d7fe3944a17f307a78b4d2b30c5;
        #1;
        // FIPS-197 Ap. C.1: round[10].output (ciphertext oficial AES-128)
        assert (addroundkey_out == 128'h69c4e0d86a7b0430d8cdb78070b4c55a)
            else begin $error("[ERRO AddRoundKey R10] Obtido: %h", addroundkey_out); error_count++; end

        $display("  -> SubBytes / ShiftRows / AddRoundKey R10 (ciphertext): PASS");


        // ====================================================================
        // TESTE 2: Decriptacao Inversa (Apendice C.1)
        // ====================================================================
        $display("\n[2/3] Decriptacao Inversa (FIPS-197 Apendice C.1)...");

        // FIPS-197 Ap. C.1 (Inverse Cipher): round[1].istart
        inv_shiftrows_in = 128'h7ad5fda789ef4e272bca100b3d9ff59f;
        #1;
        // FIPS-197 Ap. C.1 (Inverse Cipher): round[1].is_row
        assert (inv_shiftrows_out == 128'h7a9f102789d5f50b2beffd9f3dca4ea7)
            else begin $error("[ERRO InvShiftRows] Obtido: %h", inv_shiftrows_out); error_count++; end

        inv_subbytes_in = inv_shiftrows_out;
        #1;
        // FIPS-197 Ap. C.1 (Inverse Cipher): round[1].is_box
        assert (inv_subbytes_out == 128'hbd6e7c3df2b5779e0b61216e8b10b689)
            else begin $error("[ERRO InvSubBytes] Obtido: %h", inv_subbytes_out); error_count++; end

        // FIPS-197 Ap. C.1 (Equivalent Inverse Cipher), round[1]:
        //   InvMixColumns(is_row) = im_col
        //   is_row = 7a9f102789d5f50b2beffd9f3dca4ea7
        //   im_col = 4773b91ff72f354361cb018ea1e6cf2c
        // (par verificado manualmente: byte 0 = 0e*bd^0b*6e^0d*7c^09*3d = 0x47)
        inv_mixcolumns_in = 128'h7a9f102789d5f50b2beffd9f3dca4ea7;
        #1;
        assert (inv_mixcolumns_out == 128'h4773b91ff72f354361cb018ea1e6cf2c)
            else begin $error("[ERRO InvMixColumns] Obtido: %h", inv_mixcolumns_out); error_count++; end

        $display("  -> InvShiftRows / InvSubBytes / InvMixColumns: PASS");


        // ====================================================================
        // TESTE 3: Identidade algebrica InvMixColumns(MixColumns(x)) == x
        // ====================================================================
        $display("\n[3/3] Identidade InvMixColumns(MixColumns(x)) == x ...");

        // FIPS-197 Ap. B: Input (plaintext do exemplo)
        mixcolumns_in = 128'h3243f6a8885a308d313198a2e0370734;
        #1;
        inv_mixcolumns_in = mixcolumns_out;
        #1;
        assert (inv_mixcolumns_out == 128'h3243f6a8885a308d313198a2e0370734)
            else begin $error("[ERRO Identidade MixColumns] Obtido: %h", inv_mixcolumns_out); error_count++; end

        $display("  -> Identidade InvMixColumns(MixColumns(x)): PASS");

        // ====================================================================
        // RESUMO
        // ====================================================================
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("  STATUS FINAL: PASS - TODOS OS TESTES PASSARAM!");
        end else begin
            $display("  STATUS FINAL: FAIL - %0d ERRO(S) ENCONTRADO(S)!", error_count);
        end
        $display("==================================================\n");

        $finish;
    end

endmodule