// =============================================================================
// tb_semana_03  (module renamed to match `-top tb_semana_03`)
//
// Testbench da Issue #3: minisoc_aes_key_exp + minisoc_aes_dp
// Emula em software o contrato da Opção A:
//   ST_FETCH_3 : state = mem ^ rk[0]  (cipher)  |  ^ rk[10]  (InvCipher)
//   ST_EXECUTE : 10 ciclos com round_idx = round_cnt+1  (cipher)
//                                          9-round_cnt  (InvCipher)
//
// Lint NS: timing controls standalone foram encadeados a um action
// (`begin end` composto ou atribuição). Ver §3 do fix.
// =============================================================================

`timescale 1ns/1ps

module tb_semana_03;

    // -------------------------------------------------------------------------
    // Clock / Reset
    // -------------------------------------------------------------------------
    logic clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // DUTs
    // -------------------------------------------------------------------------
    minisoc_aes_key_exp u_key_exp (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (ke_start),
        .key_in    (ke_key_in),
        .round_idx (ke_round_idx),
        .round_key (ke_round_key),
        .ready     (ke_ready)
    );

    minisoc_aes_dp u_dp (
        .state_in  (dp_state_in),
        .round_cnt (dp_round_cnt),
        .round_key (dp_round_key),
        .mode      (dp_mode),
        .decrypt   (dp_decrypt),
        .state_out (dp_state_out)
    );

    // -------------------------------------------------------------------------
    // KAT vectors
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Round keys de referência (FIPS-197 Apêndice A)
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Contadores
    // -------------------------------------------------------------------------
    int errors = 0;
    int passes = 0;

    task automatic ok(input string msg);
        passes++;
        $display("  [PASS] %s", msg);
    endtask

    task automatic fail(input string msg);
        errors++;
        $error("  [FAIL] %s", msg);
    endtask

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    // Pulso de ke_start por exatamente 1 ciclo (timing attached → sem NS)
    task automatic pulse_start();
        ke_start <= 1'b1;
        @(posedge clk) ke_start <= 1'b0;
    endtask

    // Carrega key e aguarda ready; todos os timing controls encadeados.
    task automatic load_key_and_expand(input logic [127:0] key);
        ke_key_in <= key;
        pulse_start();
        // settle NBA (1ns) → wait ready → sync 1 posedge
        #1 wait (ke_ready === 1'b1) @(posedge clk) begin end
    endtask

    // Leitura combinacional de rk (sem latência adicional)
    task automatic fetch_rk(input logic [3:0] idx, output logic [127:0] rk);
        ke_round_idx = idx;
        #1 rk = ke_round_key;
    endtask

    // Avaliação combinacional de 1 rodada do dp
    task automatic eval_dp(
        input  logic [127:0] state_i,
        input  logic [3:0]   round_cnt,
        input  logic [127:0] rk,
        input  logic [2:0]   mode,
        input  logic         decrypt,
        output logic [127:0] state_o
    );
        dp_state_in  = state_i;
        dp_round_cnt = round_cnt;
        dp_round_key = rk;
        dp_mode      = mode;
        dp_decrypt   = decrypt;
        #1 state_o = dp_state_out;
    endtask

    // -------------------------------------------------------------------------
    // Core: run_cipher_ecb — emula ST_FETCH_3 + ST_EXECUTE (Opção A)
    // -------------------------------------------------------------------------
    task automatic run_cipher_ecb(
        input logic [127:0] pt,
        input logic [127:0] expected_ct,
        input string        label
    );
        logic [127:0] st, rk;
        fetch_rk(4'd0, rk);
        st = pt ^ rk;                       // ST_FETCH_3 (Opção A)
        for (int round_cnt = 0; round_cnt < 10; round_cnt++) begin
            fetch_rk(4'(round_cnt + 1), rk);
            eval_dp(st, round_cnt[3:0], rk, MODE_ECB, 1'b0, st);
        end
        if (st !== expected_ct)
            fail($sformatf("%s cipher: got %h exp %h", label, st, expected_ct));
        else
            ok($sformatf("%s cipher: %h", label, st));
    endtask

    // -------------------------------------------------------------------------
    // Core: run_inv_cipher_ecb
    // -------------------------------------------------------------------------
    task automatic run_inv_cipher_ecb(
        input logic [127:0] ct,
        input logic [127:0] expected_pt,
        input string        label
    );
        logic [127:0] st, rk;
        fetch_rk(4'd10, rk);
        st = ct ^ rk;                       // ST_FETCH_3 (Opção A)
        for (int round_cnt = 0; round_cnt < 10; round_cnt++) begin
            fetch_rk(4'(9 - round_cnt), rk);
            eval_dp(st, round_cnt[3:0], rk, MODE_ECB, 1'b1, st);
        end
        if (st !== expected_pt)
            fail($sformatf("%s InvCipher: got %h exp %h", label, st, expected_pt));
        else
            ok($sformatf("%s InvCipher: %h", label, st));
    endtask

    // -------------------------------------------------------------------------
    // Testes (§3 da Issue #3)
    // -------------------------------------------------------------------------
    task automatic test1_round_keys_kat();
        logic [127:0] rk;
        $display("\n=== Test 1: Round key KAT (C.1) ===");
        load_key_and_expand(KEY_C1);
        if (ke_ready !== 1'b1) begin
            fail("ready not high after expansion");
            return;
        end
        for (int i = 0; i <= 10; i++) begin
            fetch_rk(i[3:0], rk);
            if (rk !== ref_rk_c1[i])
                fail($sformatf("rk[%0d]: got %h exp %h", i, rk, ref_rk_c1[i]));
            else
                ok($sformatf("rk[%0d] = %h", i, rk));
        end
    endtask

    task automatic test2_cipher_c1();
        $display("\n=== Test 2: Cipher C.1 ===");
        load_key_and_expand(KEY_C1);
        run_cipher_ecb(PT_C1, CT_C1, "C.1");
    endtask

    task automatic test3_cipher_b();
        $display("\n=== Test 3: Cipher B ===");
        load_key_and_expand(KEY_B);
        run_cipher_ecb(PT_B, CT_B, "B");
    endtask

    task automatic test4_inv_cipher_c1();
        $display("\n=== Test 4: InvCipher C.1 ===");
        load_key_and_expand(KEY_C1);
        run_inv_cipher_ecb(CT_C1, PT_C1, "C.1");
    endtask

    task automatic test5_roundtrip_c1();
        $display("\n=== Test 5: Round-trip C.1 ===");
        load_key_and_expand(KEY_C1);
        run_cipher_ecb(PT_C1, CT_C1, "C.1-enc");
        run_inv_cipher_ecb(CT_C1, PT_C1, "C.1-dec");
    endtask

    task automatic test6_roundtrip_b();
        $display("\n=== Test 6: Round-trip B ===");
        load_key_and_expand(KEY_B);
        run_inv_cipher_ecb(CT_B, PT_B, "B-dec");
        run_cipher_ecb(PT_B, CT_B, "B-enc");
    endtask

    task automatic test7_reuse();
        $display("\n=== Test 7: Round key reuse ===");
        load_key_and_expand(KEY_C1);
        run_cipher_ecb(PT_C1, CT_C1, "reuse1");
        run_cipher_ecb(PT_C1, CT_C1, "reuse2");
        run_inv_cipher_ecb(CT_C1, PT_C1, "reuse3-inv");
        if (ke_ready !== 1'b1)
            fail($sformatf("ready dropped to %b during reuse", ke_ready));
        else
            ok("ready stayed high after 3 ops");
    endtask

    task automatic test8_combinational_reads();
        logic [127:0] rk;
        $display("\n=== Test 8: Combinational rk reads ===");
        load_key_and_expand(KEY_C1);
        fetch_rk(4'd0, rk);
        if (rk !== KEY_C1)
            fail($sformatf("rk[0] != key_in"));
        else
            ok($sformatf("rk[0] == key_in (%h)", rk));
        fetch_rk(4'd10, rk);
        if (rk !== ref_rk_c1[10])
            fail($sformatf("rk[10]: got %h exp %h", rk, ref_rk_c1[10]));
        else
            ok($sformatf("rk[10] = %h", rk));
        for (int i = 0; i <= 10; i++) begin
            fetch_rk(i[3:0], rk);
            if (rk !== ref_rk_c1[i])
                fail($sformatf("combinational rk[%0d] mismatch", i));
        end
    endtask

    task automatic test9_mixcolumns_timing();
        logic [127:0] st, rk;
        $display("\n=== Test 9: MixColumns timing (cipher) ===");
        load_key_and_expand(KEY_C1);
        fetch_rk(4'd0, rk);
        st = PT_C1 ^ rk;
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(4'(rc + 1), rk);
            eval_dp(st, rc[3:0], rk, MODE_ECB, 1'b0, st);
        end
        if (st !== CT_C1)
            fail($sformatf("final cipher: got %h exp %h", st, CT_C1));
        else
            ok("MixColumns timing verified (final == CT_C1)");
    endtask

    task automatic test10_invmixcolumns_timing();
        logic [127:0] st, rk;
        $display("\n=== Test 10: InvMixColumns timing ===");
        load_key_and_expand(KEY_C1);
        fetch_rk(4'd10, rk);
        st = CT_C1 ^ rk;
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(4'(9 - rc), rk);
            eval_dp(st, rc[3:0], rk, MODE_ECB, 1'b1, st);
        end
        if (st !== PT_C1)
            fail($sformatf("final InvCipher: got %h exp %h", st, PT_C1));
        else
            ok("InvMixColumns timing verified (final == PT_C1)");
    endtask

    // Caso 11: prova que o TB exercita a Opção A (mapeamento ingênuo deve falhar)
    task automatic test11_naive_mapping_rejected();
        logic [127:0] st, rk;
        $display("\n=== Test 11: Rejeição do mapeamento ingênuo ===");
        load_key_and_expand(KEY_C1);
        st = PT_C1;                         // sem XOR de rk[0]
        for (int rc = 0; rc < 10; rc++) begin
            fetch_rk(rc[3:0], rk);          // round_idx = rc
            eval_dp(st, rc[3:0], rk, MODE_ECB, 1'b0, st);
        end
        if (st === CT_C1)
            fail("mapeamento ingênuo produziu CT_C1 — TB não testa Opção A!");
        else
            ok($sformatf("mapeamento ingênuo rejeitado (got %h)", st));
    endtask

    // -------------------------------------------------------------------------
    // Sequência principal
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_semana_03.vcd");
        $dumpvars(0, tb_semana_03);

        rst_n        = 1'b0;
        ke_start     = 1'b0;
        ke_key_in    = '0;
        ke_round_idx = '0;
        dp_state_in  = '0;
        dp_round_cnt = '0;
        dp_round_key = '0;
        dp_mode      = MODE_ECB;
        dp_decrypt   = 1'b0;

        repeat (5) @(posedge clk) begin end
        rst_n = 1'b1;
        repeat (3) @(posedge clk) begin end

        test1_round_keys_kat();
        test2_cipher_c1();
        test3_cipher_b();
        test4_inv_cipher_c1();
        test5_roundtrip_c1();
        test6_roundtrip_b();
        test7_reuse();
        test8_combinational_reads();
        test9_mixcolumns_timing();
        test10_invmixcolumns_timing();
        test11_naive_mapping_rejected();

        $display("\n========================================");
        $display("  Passes : %0d", passes);
        $display("  Errors : %0d", errors);
        if (errors == 0) $display("  TEST PASSED");
        else             $display("  TEST FAILED");
        $display("========================================\n");

        $finish;
    end

    // Timeout — ação composta após o delay (silencia NS)
    initial begin
        #1_000_000 begin
            $error("TIMEOUT: simulação excedeu 1 ms");
            $finish;
        end
    end

endmodule