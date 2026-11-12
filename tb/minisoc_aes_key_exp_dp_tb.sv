// =============================================================================
// minisoc_aes_key_exp_dp_tb.sv
//
// Testbench da Issue #3 — auditoria formal contra FIPS-197 (Nov 2001).
//
// Escopo: instancia minisoc_aes_key_exp + minisoc_aes_dp e emula em software
//         a sequência Opção A (Microarquitetura v1.2 §2.2, §9.4, §9.5):
//
//   ST_FETCH_3 (emulado): state = mem ^ rk[0]   (cipher)   |  ^ rk[10]  (Inv)
//   ST_EXECUTE (emulado): 10 ciclos com round_idx = round_cnt+1  (cipher)
//                                                  9-round_cnt  (Inv)
//
// Cada teste tem 3 campos de documentação:
//   - FIPS-197 ref  : seção / figura / equação / apêndice que o teste verifica
//   - Objetivo      : que afirmação o teste estabelece
//   - Justificativa : que bug o teste pega que os outros não pegam
//
// Fora do escopo (issue do minisoc_aes_top):
//   - CDC, validação MODE/NUM_BLOCKS, XOR de chaining CBC/PCBC/CFB/OFB/CTR,
//     custo 12 + 19·N + 1, SRAM.
// =============================================================================

`timescale 1ns/1ps

module minisoc_aes_key_exp_dp_tb;

    // =========================================================================
    // Clock / Reset
    // =========================================================================
    logic clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // Sinais conectando aos DUTs
    // =========================================================================
    logic          ke_start;
    logic [127:0]  ke_key_in;
    logic [3:0]    ke_round_idx;
    logic [127:0]  ke_round_key;
    logic          ke_ready;

    logic [127:0]  dp_state_in;
    logic [3:0]    dp_round_cnt;
    logic [127:0]  dp_round_key;
    logic [2:0]    dp_mode;
    logic          dp_decrypt;
    logic [127:0]  dp_state_out;

    minisoc_aes_key_exp u_key_exp (
        .clk(clk), .rst_n(rst_n), .start(ke_start), .key_in(ke_key_in),
        .round_idx(ke_round_idx), .round_key(ke_round_key), .ready(ke_ready)
    );
    minisoc_aes_dp u_dp (
        .state_in(dp_state_in), .round_cnt(dp_round_cnt), .round_key(dp_round_key),
        .mode(dp_mode), .decrypt(dp_decrypt), .state_out(dp_state_out)
    );

    // =========================================================================
    // KAT vectors — FIPS-197 Apêndices C.1 e B
    // =========================================================================
    // Apêndice C.1 (AES-128, Nk=4, Nr=10):
    //   PLAINTEXT:   00112233445566778899aabbccddeeff
    //   KEY:         000102030405060708090a0b0c0d0e0f
    //   CIPHER out:  69c4e0d86a7b0430d8cdb78070b4c55a
    //   (linha `round[10].output` do Apêndice C.1)
    localparam logic [127:0] KEY_C1 = 128'h000102030405060708090a0b0c0d0e0f;
    localparam logic [127:0] PT_C1  = 128'h00112233445566778899aabbccddeeff;
    localparam logic [127:0] CT_C1  = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;

    // Apêndice B (AES-128, Nk=4, Nr=10):
    //   Input:      3243f6a8885a308d313198a2e0370734
    //   Cipher Key: 2b7e151628aed2a6abf7158809cf4f3c
    //   output:     3925841d02dc09fbdc118597196a0b32
    localparam logic [127:0] KEY_B  = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    localparam logic [127:0] PT_B   = 128'h3243f6a8885a308d313198a2e0370734;
    localparam logic [127:0] CT_B   = 128'h3925841d02dc09fbdc118597196a0b32;

    // Modos (§8.2 da Microarquitetura v1.2, alinhado com NIST SP 800-38A)
    localparam logic [2:0] MODE_ECB  = 3'b000;
    localparam logic [2:0] MODE_CBC  = 3'b001;
    localparam logic [2:0] MODE_PCBC = 3'b010;
    localparam logic [2:0] MODE_CFB  = 3'b011;
    localparam logic [2:0] MODE_OFB  = 3'b100;
    localparam logic [2:0] MODE_CTR  = 3'b101;

    // =========================================================================
    // Round keys de referência — FIPS-197 Apêndice A.1 + C.1
    //
    // Cada entrada ref_rk_c1[i] é EXATAMENTE o campo `round[i].k_sch`
    // publicado no Apêndice C.1 (que por sua vez coincide com o Apêndice A.1
    // — "Expansion of a 128-bit Cipher Key" — linha por linha).
    //
    // Estes valores são o oráculo do key expansion (§5.2 do FIPS, Fig. 11):
    // qualquer erro em RotWord, SubWord, Rcon ou na recorrência
    // w[i] = w[i-4] XOR temp é exposto aqui antes de qualquer teste
    // de datapath.
    // =========================================================================
    logic [127:0] ref_rk_c1 [0:10];
    initial begin
        // round[0].k_sch   — chave original (corresponde a w0..w3)
        ref_rk_c1[0]  = 128'h000102030405060708090a0b0c0d0e0f;
        // round[1].k_sch   — após 1ª iteração (w4..w7)
        ref_rk_c1[1]  = 128'hd6aa74fdd2af72fadaa678f1d6ab76fe;
        // round[2].k_sch   (w8..w11)
        ref_rk_c1[2]  = 128'hb692cf0b643dbdf1be9bc5006830b3fe;
        // round[3].k_sch   (w12..w15)
        ref_rk_c1[3]  = 128'hb6ff744ed2c2c9bf6c590cbf0469bf41;
        // round[4].k_sch   (w16..w19)
        ref_rk_c1[4]  = 128'h47f7f7bc95353e03f96c32bcfd058dfd;
        // round[5].k_sch   (w20..w23)
        ref_rk_c1[5]  = 128'h3caaa3e8a99f9deb50f3af57adf622aa;
        // round[6].k_sch   (w24..w27)
        ref_rk_c1[6]  = 128'h5e390f7df7a69296a7553dc10aa31f6b;
        // round[7].k_sch   (w28..w31)
        ref_rk_c1[7]  = 128'h14f9701ae35fe28c440adf4d4ea9c026;
        // round[8].k_sch   (w32..w35)
        ref_rk_c1[8]  = 128'h47438735a41c65b9e016baf4aebf7ad2;
        // round[9].k_sch   (w36..w39)
        ref_rk_c1[9]  = 128'h549932d1f08557681093ed9cbe2c974e;
        // round[10].k_sch  (w40..w43)
        ref_rk_c1[10] = 128'h13111d7fe3944a17f307a78b4d2b30c5;
    end

    // =========================================================================
    // Estados por rodada do CIPHER — FIPS-197 Apêndice C.1
    //
    // ref_cipher_c1[k] é EXATAMENTE o estado observado em `round[k+1].start`
    // (k=0..9) ou `round[10].output` (k=10) no Apêndice C.1.
    //
    // Convenção de indexação neste TB:
    //   ref_cipher_c1[0]  = estado logo após ST_FETCH_3
    //                     = PT ^ rk[0]  (AddRoundKey inicial, §5.1 Fig. 5)
    //                     = `round[1].start` do Apêndice C.1
    //   ref_cipher_c1[k]  = estado após round_cnt = k-1
    //                     = `round[k+1].start` do Apêndice C.1
    //   ref_cipher_c1[10] = estado após round_cnt = 9
    //                     = `round[10].output` = CT_C1
    //
    // Comparar CADA um destes 11 estados (não só o final) audita:
    //   • SubBytes  (§5.1.1, Fig. 6)    — via S-box
    //   • ShiftRows (§5.1.2, Fig. 8)    — via permutação de bytes
    //   • MixColumns(§5.1.3, Fig. 9)    — via GF(2^8) mul por {02}/{03}
    //   • AddRoundKey(§5.1.4, Fig. 10)  — via XOR com rk selecionada
    //   • ausência de MixColumns na rodada final (§5.1, Fig. 5)
    // =========================================================================
    logic [127:0] ref_cipher_c1 [0:10];
    initial begin
        // round[1].start  (após AddRoundKey inicial com rk[0])
        ref_cipher_c1[0]  = 128'h00102030405060708090a0b0c0d0e0f;
        // round[2].start  (após rodada 1: SubBytes→ShiftRows→MixColumns→^rk[1])
        ref_cipher_c1[1]  = 128'h89d810e8855ace682d1843d8cb128fe4;
        // round[3].start  (após rodada 2)
        ref_cipher_c1[2]  = 128'h4915598f55e5d7a0daca94fa1f0a63f7;
        // round[4].start  (após rodada 3)
        ref_cipher_c1[3]  = 128'hfa636a2825b339c940668a3157244d17;
        // round[5].start  (após rodada 4)
        ref_cipher_c1[4]  = 128'h247240236966b3fa6ed2753288425b6c;
        // round[6].start  (após rodada 5)
        ref_cipher_c1[5]  = 128'hc81677bc9b7ac93b25027992b0261996;
        // round[7].start  (após rodada 6)
        ref_cipher_c1[6]  = 128'hc62fe109f75eedc3cc79395d84f9cf5d;
        // round[8].start  (após rodada 7)
        ref_cipher_c1[7]  = 128'hd1876c0f79c4300ab45594add66ff41f;
        // round[9].start  (após rodada 8)
        ref_cipher_c1[8]  = 128'hfde3bad205e5d0d73547964ef1fe37f1;
        // round[10].start (após rodada 9)
        ref_cipher_c1[9]  = 128'hbd6e7c3df2b5779e0b61216e8b10b689;
        // round[10].output (após rodada 10 SEM MixColumns → ^ rk[10])
        // == CIPHER output == CT_C1
        ref_cipher_c1[10] = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    end

    // =========================================================================
    // Estados por rodada do INV Cipher — FIPS-197 Apêndice C.1
    //
    // ref_inv_c1[k] é EXATAMENTE o estado observado em `round[k+1].istart`
    // (k=0..9) ou `round[10].ioutput` (k=10).
    //
    // Convenção:
    //   ref_inv_c1[0]  = estado logo após ST_FETCH_3 em InvCipher
    //                  = CT ^ rk[10]  (§5.3.5, AddRoundKey inicial invertido)
    //                  = `round[1].istart` do Apêndice C.1
    //   ref_inv_c1[k]  = estado após round_cnt = k-1
    //                  = `round[k+1].istart` do Apêndice C.1
    //   ref_inv_c1[10] = estado após round_cnt = 9
    //                  = `round[10].ioutput` = PT_C1
    //
    // Comparar CADA estado (não só o final) audita:
    //   • InvShiftRows   (§5.3.1, Fig. 13)
    //   • InvSubBytes    (§5.3.2, Fig. 14)
    //   • InvMixColumns  (§5.3.3, Eq. 5.10)
    //   • AddRoundKey    (§5.3.4 — auto-inversa)
    //   • ORDEM específica (§5.3.5, Fig. 12): InvShiftRows→InvSubBytes→
    //                                          AddRoundKey→InvMixColumns
    //   • ausência de InvMixColumns na rodada final (§5.3.5, Fig. 12)
    // =========================================================================
    logic [127:0] ref_inv_c1 [0:10];
    initial begin
        // round[1].istart  (após AddRoundKey inicial com rk[10])
        ref_inv_c1[0]  = 128'h7ad5fda789ef4e272bca100b3d9ff59f;
        // round[2].istart  (após rodada 1: InvShiftRows→InvSubBytes→^rk[9]→InvMixColumns)
        ref_inv_c1[1]  = 128'h54d990a16ba09ab596bbf40ea111702f;
        // round[3].istart
        ref_inv_c1[2]  = 128'h3e1c22c0b6fcbf768da85067f6170495;
        // round[4].istart
        ref_inv_c1[3]  = 128'hb458124c68b68a014b99f82e5f15554c;
        // round[5].istart
        ref_inv_c1[4]  = 128'he8dab6901477d4653ff7f5e2e747dd4f;
        // round[6].istart
        ref_inv_c1[5]  = 128'h36339d50f9b539269f2c092dc4406d23;
        // round[7].istart
        ref_inv_c1[6]  = 128'h2d6d7ef03f33e334093602dd5bfb12c7;
        // round[8].istart
        ref_inv_c1[7]  = 128'h3bd92268fc74fb735767cbe0c0590e2d;
        // round[9].istart
        ref_inv_c1[8]  = 128'ha7be1a6997ad739bd8c9ca451f618b61;
        // round[10].istart (após rodada 9)
        ref_inv_c1[9]  = 128'h6353e08c0960e104cd70b751bacad0e7;
        // round[10].ioutput (após rodada 10 SEM InvMixColumns → ^ rk[0])
        // == INVERSE CIPHER output == PT_C1
        ref_inv_c1[10] = 128'h00112233445566778899aabbccddeeff;
    end

    // =========================================================================
    // Contadores
    // =========================================================================
    int errors = 0, passes = 0;

    task automatic ok(input string msg);   passes++; $display("  [PASS] %s", msg); endtask
    task automatic fail(input string msg); errors++; $error("  [FAIL] %s", msg);   endtask

    // =========================================================================
    // Helpers (timing controls encadeados — sem warnings NS)
    // =========================================================================
    task automatic pulse_start();
        ke_start <= 1'b1;
        @(posedge clk) ke_start <= 1'b0;
    endtask

    task automatic load_key_and_expand(input logic [127:0] key);
        ke_key_in <= key;
        pulse_start();
        #1 wait (ke_ready === 1'b1) @(posedge clk) begin end
    endtask

    task automatic fetch_rk(input logic [3:0] idx, output logic [127:0] rk);
        ke_round_idx = idx;
        #1 rk = ke_round_key;
    endtask

    task automatic eval_dp(
        input  logic [127:0] state_i, input logic [3:0] round_cnt,
        input  logic [127:0] rk,      input logic [2:0] mode,
        input  logic         decrypt, output logic [127:0] state_o
    );
        dp_state_in  = state_i;
        dp_round_cnt = round_cnt;
        dp_round_key = rk;
        dp_mode      = mode;
        dp_decrypt   = decrypt;
        #1 state_o = dp_state_out;
    endtask

    // =========================================================================
    // run_cipher_ecb_traced — emula ST_FETCH_3 + ST_EXECUTE e compara
    // POR RODADA contra ref_cipher_c1 (Apêndice C.1).
    // =========================================================================
    task automatic run_cipher_ecb_traced(
        input logic [127:0] pt, input logic [127:0] expected_ct, input string label
    );
        logic [127:0] st, rk;
        // ST_FETCH_3 (Opção A, §2.4 da Issue #2): st = pt ^ rk[0]
        fetch_rk(4'd0, rk);
        st = pt ^ rk;
        if (st !== ref_cipher_c1[0])
            fail($sformatf("%s cipher FETCH_3: got %h exp %h", label, st, ref_cipher_c1[0]));
        // ST_EXECUTE: 10 ciclos, round_idx = round_cnt+1 (§9.5)
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(4'(rc + 1), rk);
            eval_dp(st, rc[3:0], rk, MODE_ECB, 1'b0, st);
            if (st !== ref_cipher_c1[rc + 1])
                fail($sformatf("%s cipher round %0d: got %h exp %h",
                                label, rc, st, ref_cipher_c1[rc + 1]));
        end
        if (st === expected_ct)
            ok($sformatf("%s cipher (11 estados FIPS-197 C.1 conferem)", label));
        else
            fail($sformatf("%s cipher final: got %h exp %h", label, st, expected_ct));
    endtask

    // =========================================================================
    // run_inv_cipher_ecb_traced — análogo para InvCipher (§5.3, Fig. 12).
    // =========================================================================
    task automatic run_inv_cipher_ecb_traced(
        input logic [127:0] ct, input logic [127:0] expected_pt, input string label
    );
        logic [127:0] st, rk;
        // ST_FETCH_3 (Opção A): st = ct ^ rk[10]
        fetch_rk(4'd10, rk);
        st = ct ^ rk;
        if (st !== ref_inv_c1[0])
            fail($sformatf("%s InvCipher FETCH_3: got %h exp %h", label, st, ref_inv_c1[0]));
        // ST_EXECUTE: 10 ciclos, round_idx = 9-round_cnt (§9.5)
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(4'(9 - rc), rk);
            eval_dp(st, rc[3:0], rk, MODE_ECB, 1'b1, st);
            if (st !== ref_inv_c1[rc + 1])
                fail($sformatf("%s InvCipher round %0d: got %h exp %h",
                                label, rc, st, ref_inv_c1[rc + 1]));
        end
        if (st === expected_pt)
            ok($sformatf("%s InvCipher (11 estados FIPS-197 C.1 conferem)", label));
        else
            fail($sformatf("%s InvCipher final: got %h exp %h", label, st, expected_pt));
    endtask

    // =========================================================================
    // TEST 1 — Round key KAT (FIPS-197 Apêndice A.1)
    // -------------------------------------------------------------------------
    // FIPS-197 ref : §5.2 Key Expansion (Fig. 11) + Apêndice A.1
    // Objetivo     : os 11 round keys produzidos pelo RTL coincidem com a
    //                tabela linha-a-linha do Apêndice A.1, i.e.
    //                rk_bank[i] == round[i].k_sch para i = 0..10.
    // Justificativa: isola o key_exp de qualquer erro do datapath. Se RotWord,
    //                SubWord, Rcon ou a recorrência w[i]=w[i-4]^temp estiverem
    //                errados, TODOS os outros testes falhariam — este mostra
    //                imediatamente QUAL round key está errada (bisecção).
    // =========================================================================
    task automatic test1_round_keys_kat();
        logic [127:0] rk;
        $display("\n=== Test 1: Round key KAT (FIPS-197 A.1 / C.1) ===");
        load_key_and_expand(KEY_C1);
        if (ke_ready !== 1'b1) begin fail("ready not high"); return; end
        for (int i = 0; i <= 10; i++) begin
            fetch_rk(i[3:0], rk);
            if (rk !== ref_rk_c1[i])
                fail($sformatf("rk[%0d]: got %h exp %h", i, rk, ref_rk_c1[i]));
            else
                ok($sformatf("rk[%0d] = %h", i, rk));
        end
    endtask

    // =========================================================================
    // TEST 2 — Cipher C.1, verificação POR RODADA
    // -------------------------------------------------------------------------
    // FIPS-197 ref : §5.1 Cipher (Fig. 5) + Apêndice C.1 (linha C.1 ENCRYPT)
    // Objetivo     : a sequência completa
    //                  FETCH_3 → SubBytes → ShiftRows → MixColumns → ^rk
    //                  (×9) → SubBytes → ShiftRows → ^rk (rodada final)
    //                reproduz os 11 estados `round[k].start` / `round[10].output`.
    // Justificativa: comparar só o final mascara erros em rodadas individuais
    //                que se cancelam em pares. Este teste falha na PRIMEIRA
    //                rodada que divergir do FIPS, expondo exatamente qual
    //                transformação quebrou (SubBytes? ShiftRows? MixColumns?
    //                ordem do XOR com rk?).
    // =========================================================================
    task automatic test2_cipher_c1();
        $display("\n=== Test 2: Cipher C.1 (11 estados FIPS-197 C.1) ===");
        load_key_and_expand(KEY_C1);
        run_cipher_ecb_traced(PT_C1, CT_C1, "C.1");
    endtask

    // =========================================================================
    // TEST 3 — Cipher Apêndice B (chave diferente)
    // -------------------------------------------------------------------------
    // FIPS-197 ref : Apêndice B (vetor independente de C.1)
    // Objetivo     : o datapath continua correto com uma chave diferente —
    //                confirma que não há coincidência acidental em C.1.
    // Justificativa: complementa Test 2 com um segundo par (PT,CT) oficial.
    //                O Apêndice B não publica estados por rodada, então só
    //                o resultado final é comparado; a cobertura por rodada
    //                já está no Test 2.
    // =========================================================================
    task automatic test3_cipher_b();
        $display("\n=== Test 3: Cipher Apêndice B (chave 2b7e1516...) ===");
        load_key_and_expand(KEY_B);
        // Sem refs por rodada publicadas em B — usa só o estado final.
        logic [127:0] st, rk;
        fetch_rk(4'd0, rk); st = PT_B ^ rk;
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(4'(rc + 1), rk);
            eval_dp(st, rc[3:0], rk, MODE_ECB, 1'b0, st);
        end
        if (st === CT_B) ok($sformatf("B cipher final: %h", st));
        else             fail($sformatf("B cipher final: got %h exp %h", st, CT_B));
    endtask

    // =========================================================================
    // TEST 4 — InvCipher C.1, verificação POR RODADA
    // -------------------------------------------------------------------------
    // FIPS-197 ref : §5.3 Inverse Cipher (Fig. 12) + Apêndice C.1 DECRYPT
    // Objetivo     : a sequência
    //                  FETCH_3 → InvShiftRows → InvSubBytes → ^rk
    //                  → InvMixColumns (×9) → InvShiftRows → InvSubBytes
    //                  → ^rk (rodada final, SEM InvMixColumns)
    //                reproduz os 11 estados `round[k].istart` / `round[10].ioutput`.
    // Justificativa: além de checar cada transformação inversa, verifica
    //                a ORDEM específica de §5.3.5 (AddRoundKey ANTES de
    //                InvMixColumns, ao contrário do Cipher). Se a ordem for
    //                trocada, a rodada 1 já diverge de ref_inv_c1[1].
    // =========================================================================
    task automatic test4_inv_cipher_c1();
        $display("\n=== Test 4: InvCipher C.1 (11 estados FIPS-197 C.1) ===");
        load_key_and_expand(KEY_C1);
        run_inv_cipher_ecb_traced(CT_C1, PT_C1, "C.1");
    endtask

    // =========================================================================
    // TEST 5 — Round-trip C.1
    // -------------------------------------------------------------------------
    // FIPS-197 ref : corolário de §5.1 + §5.3 (Inverse Cipher desfaz Cipher)
    // Objetivo     : InvCipher(Cipher(PT)) == PT, ponta a ponta, com a
    //                MESMA chave expandida (rk_bank congelado entre as duas).
    // Justificativa: verifica a integração "cifra depois decifra" — pega bugs
    //                em que as duas direções estão corretas individualmente
    //                mas usam round keys em ordens inconsistentes entre elas.
    // =========================================================================
    task automatic test5_roundtrip_c1();
        $display("\n=== Test 5: Round-trip C.1 (InvCipher∘Cipher == id) ===");
        load_key_and_expand(KEY_C1);
        run_cipher_ecb_traced(PT_C1, CT_C1, "C.1-enc");
        run_inv_cipher_ecb_traced(CT_C1, PT_C1, "C.1-dec");
    endtask

    // =========================================================================
    // TEST 7 — Reuso do key expansion entre operações
    // -------------------------------------------------------------------------
    // FIPS-197 ref : §5.2 — a expansão é função SÓ da chave; pode ser feita
    //                uma vez e reutilizada por múltiplas operações.
    // Objetivo     : após 3 operações consecutivas sem re-expandir, rk_bank
    //                permanece válido (ready sticky, valores idênticos).
    // Justificativa: confirma o contrato do minisoc_aes_key_exp (§10.8.4) e
    //                do §9.3 (KEY_EXP roda uma vez por operação, não por
    //                bloco). Se ready caísse entre operações, ou se rk_bank
    //                fosse corrompido por um start espúrio, este teste falha.
    // =========================================================================
    task automatic test7_reuse();
        $display("\n=== Test 7: Reuso do key expansion (ready sticky) ===");
        load_key_and_expand(KEY_C1);
        run_cipher_ecb_traced(PT_C1, CT_C1, "reuse1");
        run_cipher_ecb_traced(PT_C1, CT_C1, "reuse2");
        run_inv_cipher_ecb_traced(CT_C1, PT_C1, "reuse3-inv");
        if (ke_ready !== 1'b1) fail("ready dropped");
        else                   ok("ready stayed high after 3 ops");
    endtask

    // =========================================================================
    // TEST 8 — Leitura combinacional de rk[0..10]
    // -------------------------------------------------------------------------
    // FIPS-197 ref : §5.1 (AddRoundKey inicial usa rk[0]) e §5.3.5 (Inv usa rk[10]);
    //                §5.2 garante que estes valores existem no key schedule.
    // Objetivo     : com ready=1, o mux 11:1 combinacional de round_key devolve
    //                rk_bank[round_idx] SEM latência adicional, para todo
    //                round_idx ∈ [0,10].
    // Justificativa: valida o contrato §10.4 do minisoc_aes_key_exp — se o
    //                mux não fosse combinacional, ST_FETCH_3 (que lê rk[0]/
    //                rk[10] num único ciclo) e ST_EXECUTE (que troca rk a
    //                cada ciclo) ambos leriam valores atrasados. Este teste
    //                detecta latência acidental antes que ela apareça como
    //                falha enigmática de KAT.
    // =========================================================================
    task automatic test8_combinational_reads();
        logic [127:0] rk;
        $display("\n=== Test 8: Leitura combinacional de rk[0..10] ===");
        load_key_and_expand(KEY_C1);
        // Caso crítico: rk[0] deve ser EXATAMENTE key_in (round[0].k_sch)
        fetch_rk(4'd0, rk);
        if (rk !== KEY_C1) fail("rk[0] != key_in"); else ok("rk[0] == key_in");
        // Varredura completa confirma que o mux não tem "buracos"
        for (int i = 0; i <= 10; i++) begin
            fetch_rk(i[3:0], rk);
            if (rk !== ref_rk_c1[i]) fail($sformatf("rk[%0d] mismatch", i));
        end
    endtask

    // =========================================================================
    // TEST 11 — Rejeição do mapeamento "ingênuo"
    // -------------------------------------------------------------------------
    // FIPS-197 ref : §5.1 Fig. 5 — o pseudocódigo TEM uma chamada explícita
    //                de AddRoundKey(state, w[0..Nb-1]) ANTES do loop das
    //                rodadas. Sem ela, o AES está errado.
    // Objetivo     : reproduzir a variante SEM essa chamada inicial e SEM
    //                rk[10], com round_idx=round_cnt — e confirmar que
    //                produz um resultado DIFERENTE de CT_C1.
    // Justificativa: é o meta-teste que prova que os testes 2/4/5 NÃO são
    //                verdes por acidente. Se o TB estivesse, por bug próprio,
    //                aceitando o mapeamento ingênuo, este teste viraria
    //                "fail" e denunciaria o problema. É a garantia de que a
    //                Opção A está REALMENTE sendo exercitada.
    // =========================================================================
    task automatic test11_naive_mapping_rejected();
        logic [127:0] st, rk;
        $display("\n=== Test 11: Mapeamento ingênuo rejeitado ===");
        load_key_and_expand(KEY_C1);
        st = PT_C1;
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(rc[3:0], rk);        // round_idx = rc (rk[0..9])
            eval_dp(st, rc[3:0], rk, MODE_ECB, 1'b0, st);
        end
        if (st === CT_C1) fail("mapeamento ingênuo produziu CT_C1");
        else              ok($sformatf("mapeamento ingênuo rejeitado (got %h)", st));
    endtask

    // =========================================================================
    // TEST 12 — decrypt=1 em CFB/OFB/CTR deve ser IGNORADO
    // -------------------------------------------------------------------------
    // Ref combinada:
    //   • FIPS-197 §5.1 — CFB/OFB/CTR usam SEMPRE a função Cipher como
    //     primitiva (definição em NIST SP 800-38A, referenciada por FIPS-197 §1).
    //   • Microarquitetura v1.2 §9.9 — "DECRYPT=1 em CFB/OFB/CTR não é erro;
    //     é ignorado. O datapath força use_inv = 0."
    // Objetivo     : com decrypt=1 e mode ∈ {CFB, OFB, CTR}, a saída deve ser
    //                IDÊNTICA ao caminho Cipher puro (ECB encrypt).
    // Justificativa: exercita a expressão §3.3 da Issue #2
    //                  use_inv = decrypt & (mode ∉ {CFB, OFB, CTR})
    //                Um erro clássico é esquecer o AND com mode, fazendo
    //                "decrypt=1" ativar InvCipher em modos de fluxo — o que
    //                quebraria silenciosamente CFB/OFB/CTR. Este teste pega
    //                exatamente esse cenário.
    // =========================================================================
    task automatic test12_stream_decrypt_ignored();
        logic [127:0] st_ecb, rk;
        $display("\n=== Test 12: decrypt=1 em CFB/OFB/CTR == Cipher (ignorado) ===");
        load_key_and_expand(KEY_C1);

        // Referência "ouro": Cipher ECB com decrypt=0 (use_inv=0)
        fetch_rk(4'd0, rk); st_ecb = PT_C1 ^ rk;
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(4'(rc + 1), rk);
            eval_dp(st_ecb, rc[3:0], rk, MODE_ECB, 1'b0, st_ecb);
        end

        // CFB/OFB/CTR com decrypt=1 DEVEM produzir o mesmo st_ecb
        begin : stream_modes
            automatic logic [2:0] modes [0:2] = '{MODE_CFB, MODE_OFB, MODE_CTR};
            automatic string      names [0:2] = '{"CFB", "OFB", "CTR"};
            for (int m = 0; m < 3; m++) begin
                logic [127:0] st_m;
                fetch_rk(4'd0, rk); st_m = PT_C1 ^ rk;
                for (int rc = 0; rc < 10; rc++) begin
                    fetch_rk(4'(rc + 1), rk);
                    eval_dp(st_m, rc[3:0], rk, modes[m], 1'b1, st_m);
                end
                if (st_m === st_ecb)
                    ok($sformatf("%s decrypt=1 = Cipher (use_inv=0 confirmado)", names[m]));
                else
                    fail($sformatf("%s decrypt=1 divergiu: got %h exp %h",
                                    names[m], st_m, st_ecb));
            end
        end
    endtask

    // =========================================================================
    // TEST 13 — decrypt=1 em CBC/PCBC deve usar InvCipher
    // -------------------------------------------------------------------------
    // FIPS-197 ref : §5.3 (Inverse Cipher) — para CBC/PCBC em decifra,
    //                a primitiva é InvCipher (§8.2 da Microarquitetura,
    //                alinhado com NIST SP 800-38A §6.2/§7.2).
    // Objetivo     : com decrypt=1 e mode ∈ {CBC, PCBC}, a primitiva
    //                selecionada deve ser InvCipher — i.e.
    //                InvCipher(CT_C1) = PT_C1.
    // Justificativa: completa Test 12 no sentido oposto. Juntos, Test 12 +
    //                Test 13 verificam TODAS as combinações da tabela §2.3
    //                da Issue #2 (ECB/CBC/PCBC × decrypt × CFB/OFB/CTR).
    //                Antes desses dois testes, use_inv estava validado apenas
    //                para ECB — os 5 outros modos nunca tinham sido tocados.
    // =========================================================================
    task automatic test13_block_decrypt_uses_inv();
        logic [127:0] st, rk;
        $display("\n=== Test 13: CBC/PCBC decrypt=1 usa InvCipher ===");
        load_key_and_expand(KEY_C1);
        begin : block_modes
            automatic logic [2:0] modes [0:1] = '{MODE_CBC, MODE_PCBC};
            automatic string      names [0:1] = '{"CBC", "PCBC"};
            for (int m = 0; m < 2; m++) begin
                fetch_rk(4'd10, rk); st = CT_C1 ^ rk;
                for (int rc = 0; rc < 10; rc++) begin
                    fetch_rk(4'(9 - rc), rk);
                    eval_dp(st, rc[3:0], rk, modes[m], 1'b1, st);
                end
                if (st === PT_C1)
                    ok($sformatf("%s decrypt=1 → InvCipher (use_inv=1)", names[m]));
                else
                    fail($sformatf("%s decrypt=1 não foi InvCipher: got %h exp %h",
                                    names[m], st, PT_C1));
            end
        end
    endtask

    // =========================================================================
    // Sequência principal
    // =========================================================================
    initial begin
        $dumpfile("minisoc_aes_key_exp_dp_tb.vcd");
        $dumpvars(0, minisoc_aes_key_exp_dp_tb);

        rst_n = 1'b0; ke_start = 1'b0; ke_key_in = '0; ke_round_idx = '0;
        dp_state_in = '0; dp_round_cnt = '0; dp_round_key = '0;
        dp_mode = MODE_ECB; dp_decrypt = 1'b0;

        repeat (5) @(posedge clk) begin end
        rst_n = 1'b1;
        repeat (3) @(posedge clk) begin end

        test1_round_keys_kat();
        test2_cipher_c1();
        test3_cipher_b();
        test4_inv_cipher_c1();
        test5_roundtrip_c1();
        test7_reuse();
        test8_combinational_reads();
        test11_naive_mapping_rejected();
        test12_stream_decrypt_ignored();
        test13_block_decrypt_uses_inv();

        $display("\n========================================");
        $display("  Passes : %0d", passes);
        $display("  Errors : %0d", errors);
        if (errors == 0) $display("  TEST PASSED");
        else             $display("  TEST FAILED");
        $display("========================================\n");
        $finish;
    end

    // Timeout — ação composta silencia NS
    initial begin
        #1_000_000 begin
            $error("TIMEOUT");
            $finish;
        end
    end

endmodule