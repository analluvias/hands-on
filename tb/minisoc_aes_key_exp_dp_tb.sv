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
// Regra estrutural (VCS em modo estrito):
//   Toda declaração de variável vem ANTES do primeiro statement executável
//   dentro de cada task/bloco. int do cabeçalho do for é a única exceção.
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
    localparam logic [127:0] KEY_C1 = 128'h000102030405060708090a0b0c0d0e0f;
    localparam logic [127:0] PT_C1  = 128'h00112233445566778899aabbccddeeff;
    localparam logic [127:0] CT_C1  = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;

    localparam logic [127:0] KEY_B  = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    localparam logic [127:0] PT_B   = 128'h3243f6a8885a308d313198a2e0370734;
    localparam logic [127:0] CT_B   = 128'h3925841d02dc09fbdc118597196a0b32;

    localparam logic [2:0] MODE_ECB  = 3'b000;
    localparam logic [2:0] MODE_CBC  = 3'b001;
    localparam logic [2:0] MODE_PCBC = 3'b010;
    localparam logic [2:0] MODE_CFB  = 3'b011;
    localparam logic [2:0] MODE_OFB  = 3'b100;
    localparam logic [2:0] MODE_CTR  = 3'b101;

    // =========================================================================
    // Round keys de referência — FIPS-197 Apêndice A.1 / C.1
    // ref_rk_c1[i] == round[i].k_sch
    // =========================================================================
    logic [127:0] ref_rk_c1 [0:10];
    initial begin
        ref_rk_c1[0]  = 128'h000102030405060708090a0b0c0d0e0f;
        ref_rk_c1[1]  = 128'hd6aa74fdd2af72fadaa678f1d6ab76fe;
        ref_rk_c1[2]  = 128'hb692cf0b643dbdf1be9bc5006830b3fe;
        ref_rk_c1[3]  = 128'hb6ff744ed2c2c9bf6c590cbf0469bf41;
        ref_rk_c1[4]  = 128'h47f7f7bc95353e03f96c32bcfd058dfd;
        ref_rk_c1[5]  = 128'h3caaa3e8a99f9deb50f3af57adf622aa;
        ref_rk_c1[6]  = 128'h5e390f7df7a69296a7553dc10aa31f6b;
        ref_rk_c1[7]  = 128'h14f9701ae35fe28c440adf4d4ea9c026;
        ref_rk_c1[8]  = 128'h47438735a41c65b9e016baf4aebf7ad2;
        ref_rk_c1[9]  = 128'h549932d1f08557681093ed9cbe2c974e;
        ref_rk_c1[10] = 128'h13111d7fe3944a17f307a78b4d2b30c5;
    end

    // =========================================================================
    // Estados por rodada do CIPHER — FIPS-197 Apêndice C.1
    // =========================================================================
    logic [127:0] ref_cipher_c1 [0:10];
    initial begin
        ref_cipher_c1[0]  = 128'h00102030405060708090a0b0c0d0e0f; // round[1].start
        ref_cipher_c1[1]  = 128'h89d810e8855ace682d1843d8cb128fe4; // round[2].start
        ref_cipher_c1[2]  = 128'h4915598f55e5d7a0daca94fa1f0a63f7; // round[3].start
        ref_cipher_c1[3]  = 128'hfa636a2825b339c940668a3157244d17; // round[4].start
        ref_cipher_c1[4]  = 128'h247240236966b3fa6ed2753288425b6c; // round[5].start
        ref_cipher_c1[5]  = 128'hc81677bc9b7ac93b25027992b0261996; // round[6].start
        ref_cipher_c1[6]  = 128'hc62fe109f75eedc3cc79395d84f9cf5d; // round[7].start
        ref_cipher_c1[7]  = 128'hd1876c0f79c4300ab45594add66ff41f; // round[8].start
        ref_cipher_c1[8]  = 128'hfde3bad205e5d0d73547964ef1fe37f1; // round[9].start
        ref_cipher_c1[9]  = 128'hbd6e7c3df2b5779e0b61216e8b10b689; // round[10].start
        ref_cipher_c1[10] = 128'h69c4e0d86a7b0430d8cdb78070b4c55a; // round[10].output
    end

    // =========================================================================
    // Estados por rodada do INV Cipher — FIPS-197 Apêndice C.1
    // =========================================================================
    logic [127:0] ref_inv_c1 [0:10];
    initial begin
        ref_inv_c1[0]  = 128'h7ad5fda789ef4e272bca100b3d9ff59f; // round[1].istart
        ref_inv_c1[1]  = 128'h54d990a16ba09ab596bbf40ea111702f; // round[2].istart
        ref_inv_c1[2]  = 128'h3e1c22c0b6fcbf768da85067f6170495; // round[3].istart
        ref_inv_c1[3]  = 128'hb458124c68b68a014b99f82e5f15554c; // round[4].istart
        ref_inv_c1[4]  = 128'he8dab6901477d4653ff7f5e2e747dd4f; // round[5].istart
        ref_inv_c1[5]  = 128'h36339d50f9b539269f2c092dc4406d23; // round[6].istart
        ref_inv_c1[6]  = 128'h2d6d7ef03f33e334093602dd5bfb12c7; // round[7].istart
        ref_inv_c1[7]  = 128'h3bd92268fc74fb735767cbe0c0590e2d; // round[8].istart
        ref_inv_c1[8]  = 128'ha7be1a6997ad739bd8c9ca451f618b61; // round[9].istart
        ref_inv_c1[9]  = 128'h6353e08c0960e104cd70b751bacad0e7; // round[10].istart
        ref_inv_c1[10] = 128'h00112233445566778899aabbccddeeff; // round[10].ioutput
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
    // run_cipher_ecb_traced — ST_FETCH_3 + ST_EXECUTE contra Apêndice C.1
    // =========================================================================
    task automatic run_cipher_ecb_traced(
        input logic [127:0] pt, input logic [127:0] expected_ct, input string label
    );
        logic [127:0] st, rk;                                  // decls no topo
        fetch_rk(4'd0, rk);
        st = pt ^ rk;                                          // ST_FETCH_3
        if (st !== ref_cipher_c1[0])
            fail($sformatf("%s cipher FETCH_3: got %h exp %h", label, st, ref_cipher_c1[0]));
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
    // run_inv_cipher_ecb_traced — InvCipher contra Apêndice C.1
    // =========================================================================
    task automatic run_inv_cipher_ecb_traced(
        input logic [127:0] ct, input logic [127:0] expected_pt, input string label
    );
        logic [127:0] st, rk;                                  // decls no topo
        fetch_rk(4'd10, rk);
        st = ct ^ rk;
        if (st !== ref_inv_c1[0])
            fail($sformatf("%s InvCipher FETCH_3: got %h exp %h", label, st, ref_inv_c1[0]));
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
    // TEST 1 — Round key KAT (FIPS-197 A.1 / C.1)
    // =========================================================================
    task automatic test1_round_keys_kat();
        logic [127:0] rk;                                      // decl no topo
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
    // =========================================================================
    task automatic test2_cipher_c1();
        $display("\n=== Test 2: Cipher C.1 (11 estados FIPS-197 C.1) ===");
        load_key_and_expand(KEY_C1);
        run_cipher_ecb_traced(PT_C1, CT_C1, "C.1");
    endtask

    // =========================================================================
    // TEST 3 — Cipher Apêndice B
    // (decl movido para o TOPO — corrige o erro de sintaxe da linha 379)
    // =========================================================================
    task automatic test3_cipher_b();
        logic [127:0] st, rk;                                  // DECL NO TOPO
        $display("\n=== Test 3: Cipher Apêndice B (chave 2b7e1516...) ===");
        load_key_and_expand(KEY_B);
        fetch_rk(4'd0, rk);
        st = PT_B ^ rk;
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(4'(rc + 1), rk);
            eval_dp(st, rc[3:0], rk, MODE_ECB, 1'b0, st);
        end
        if (st === CT_B) ok($sformatf("B cipher final: %h", st));
        else             fail($sformatf("B cipher final: got %h exp %h", st, CT_B));
    endtask

    // =========================================================================
    // TEST 4 — InvCipher C.1, verificação POR RODADA
    // =========================================================================
    task automatic test4_inv_cipher_c1();
        $display("\n=== Test 4: InvCipher C.1 (11 estados FIPS-197 C.1) ===");
        load_key_and_expand(KEY_C1);
        run_inv_cipher_ecb_traced(CT_C1, PT_C1, "C.1");
    endtask

    // =========================================================================
    // TEST 5 — Round-trip C.1
    // =========================================================================
    task automatic test5_roundtrip_c1();
        $display("\n=== Test 5: Round-trip C.1 (InvCipher∘Cipher == id) ===");
        load_key_and_expand(KEY_C1);
        run_cipher_ecb_traced(PT_C1, CT_C1, "C.1-enc");
        run_inv_cipher_ecb_traced(CT_C1, PT_C1, "C.1-dec");
    endtask

    // =========================================================================
    // TEST 7 — Reuso do key expansion entre operações
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
    // =========================================================================
    task automatic test8_combinational_reads();
        logic [127:0] rk;                                      // decl no topo
        $display("\n=== Test 8: Leitura combinacional de rk[0..10] ===");
        load_key_and_expand(KEY_C1);
        fetch_rk(4'd0, rk);
        if (rk !== KEY_C1) fail("rk[0] != key_in"); else ok("rk[0] == key_in");
        for (int i = 0; i <= 10; i++) begin
            fetch_rk(i[3:0], rk);
            if (rk !== ref_rk_c1[i]) fail($sformatf("rk[%0d] mismatch", i));
        end
    endtask

    // =========================================================================
    // TEST 11 — Rejeição do mapeamento ingênuo
    // =========================================================================
    task automatic test11_naive_mapping_rejected();
        logic [127:0] st, rk;                                  // decl no topo
        $display("\n=== Test 11: Mapeamento ingênuo rejeitado ===");
        load_key_and_expand(KEY_C1);
        st = PT_C1;
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(rc[3:0], rk);
            eval_dp(st, rc[3:0], rk, MODE_ECB, 1'b0, st);
        end
        if (st === CT_C1) fail("mapeamento ingênuo produziu CT_C1");
        else              ok($sformatf("mapeamento ingênuo rejeitado (got %h)", st));
    endtask

    // =========================================================================
    // TEST 12 — decrypt=1 em CFB/OFB/CTR deve ser IGNORADO
    // (reescrito sem automatic array '{...}': usa case + variáveis pré-declaradas)
    // =========================================================================
    task automatic test12_stream_decrypt_ignored();
        logic [127:0] st_ecb, st_m, rk;                        // decls no topo
        logic [2:0]   mode_m;
        string        name_m;
        $display("\n=== Test 12: decrypt=1 em CFB/OFB/CTR == Cipher (ignorado) ===");
        load_key_and_expand(KEY_C1);

        // Referência "ouro": ECB encrypt (use_inv = 0)
        fetch_rk(4'd0, rk); st_ecb = PT_C1 ^ rk;
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(4'(rc + 1), rk);
            eval_dp(st_ecb, rc[3:0], rk, MODE_ECB, 1'b0, st_ecb);
        end

        // CFB/OFB/CTR com decrypt=1 → DEVEM produzir st_ecb
        for (int m = 0; m < 3; m++) begin
            case (m)
                0: begin mode_m = MODE_CFB; name_m = "CFB"; end
                1: begin mode_m = MODE_OFB; name_m = "OFB"; end
                default: begin mode_m = MODE_CTR; name_m = "CTR"; end
            endcase
            fetch_rk(4'd0, rk); st_m = PT_C1 ^ rk;
            for (int rc = 0; rc < 10; rc++) begin
                fetch_rk(4'(rc + 1), rk);
                eval_dp(st_m, rc[3:0], rk, mode_m, 1'b1, st_m);
            end
            if (st_m === st_ecb)
                ok($sformatf("%s decrypt=1 = Cipher (use_inv=0 confirmado)", name_m));
            else
                fail($sformatf("%s decrypt=1 divergiu: got %h exp %h",
                                name_m, st_m, st_ecb));
        end
    endtask

    // =========================================================================
    // TEST 13 — decrypt=1 em CBC/PCBC deve usar InvCipher
    // (mesma técnica do Test 12)
    // =========================================================================
    task automatic test13_block_decrypt_uses_inv();
        logic [127:0] st, rk;                                  // decls no topo
        logic [2:0]   mode_m;
        string        name_m;
        $display("\n=== Test 13: CBC/PCBC decrypt=1 usa InvCipher ===");
        load_key_and_expand(KEY_C1);
        for (int m = 0; m < 2; m++) begin
            if (m == 0) begin mode_m = MODE_CBC;  name_m = "CBC";  end
            else        begin mode_m = MODE_PCBC; name_m = "PCBC"; end
            fetch_rk(4'd10, rk); st = CT_C1 ^ rk;
            for (int rc = 0; rc < 10; rc++) begin
                fetch_rk(4'(9 - rc), rk);
                eval_dp(st, rc[3:0], rk, mode_m, 1'b1, st);
            end
            if (st === PT_C1)
                ok($sformatf("%s decrypt=1 → InvCipher (use_inv=1)", name_m));
            else
                fail($sformatf("%s decrypt=1 não foi InvCipher: got %h exp %h",
                                name_m, st, PT_C1));
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