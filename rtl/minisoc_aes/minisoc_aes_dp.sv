// =============================================================================
// minisoc_aes_dp.sv
//
// AES-128 datapath — uma rodada por ciclo, Cipher + InvCipher.
// Conforme Issue #2 e Microarquitetura v1.2 8.1 / 9.5 / 2 (Opção A).
//
// Contrato com a FSM (minisoc_aes_top, issue futura):
//   - state_in já contém o XOR de encadeamento de modo E a round key
//     inicial (rk[0] em cipher, rk[10] em InvCipher), aplicados em
//     ST_FETCH_3 (9.4). O datapath NÃO aplica rk inicial.
//   - round_key é selecionada pela FSM via key_exp.round_idx:
//       cipher     : round_idx = round_cnt + 1  → rk[1..10]
//       inv_cipher : round_idx = 9 - round_cnt  → rk[9..0]
//   - round_cnt = 0..9; round_cnt == 9 desabilita MixColumns/InvMixColumns
//     (rodada final, FIPS-197 §5.1 / 5.3.5).
//   - decrypt em CFB/OFB/CTR é IGNORADO (sempre Cipher), conforme 9.9.
//
// Estrutura das rodadas (FIPS-197):
//   Cipher    : SubBytes → ShiftRows → [MixColumns] → AddRoundKey
//   InvCipher : InvShiftRows → InvSubBytes → AddRoundKey → [InvMixColumns]
//
// Muxes:
//   - Mux de rodada final (is_final): escolhe entre com/sem Mix(Inv)Columns.
//   - Mux final (use_inv): escolhe a cadeia inteira (Cipher vs InvCipher).
//     As duas cadeias rodam em paralelo a partir de state_in; o mux final
//     fica DEPOIS de ambas — SubBytes/ShiftRows não estão no caminho do mux.
// =============================================================================

module minisoc_aes_dp (
    input  logic [127:0] state_in,      // bloco já com rk inicial e XOR de modo
    input  logic [3:0]   round_cnt,     // 0..9 (ciclo dentro de ST_EXECUTE)
    input  logic [127:0] round_key,     // rk selecionada pela FSM
    input  logic [2:0]   mode,          // 000=ECB,001=CBC,010=PCBC,011=CFB,100=OFB,101=CTR
    input  logic         decrypt,       // sh_decrypt
    output logic [127:0] state_out
);

    // -------------------------------------------------------------------------
    // Seleção do primitive (§2.3)
    //
    //   use_inv = decrypt & (mode ∈ {ECB, CBC, PCBC})
    //
    // CFB/OFB/CTR: decrypt=1 é IGNORADO — não é erro, sempre Cipher (9.9).
    // -------------------------------------------------------------------------
    wire use_inv = decrypt
                 & (mode != 3'b011)   // CFB
                 & (mode != 3'b100)   // OFB
                 & (mode != 3'b101);  // CTR

    // Rodada final (round_cnt == 9): sem MixColumns / InvMixColumns
    wire is_final = (round_cnt == 4'd9);

    // =========================================================================
    // Cipher path (FIPS-197 5.1)
    //
    //   SubBytes(state_in) → ShiftRows → [MixColumns] → AddRoundKey(rk)
    //   MixColumns é pulado na rodada final (round_cnt == 9).
    // =========================================================================
    logic [127:0] ciph_sb;      // SubBytes(state_in)
    logic [127:0] ciph_sr;      // ShiftRows(ciph_sb)
    logic [127:0] ciph_mc;      // MixColumns(ciph_sr)
    logic [127:0] ciph_pre_ark; // Mux da rodada final (com/sem MixColumns)
    logic [127:0] ciph_final;   // AddRoundKey(ciph_pre_ark, round_key)

    minisoc_aes_sub_bytes   u_c_sb (.state_in(state_in), .state_out(ciph_sb));
    minisoc_aes_shift_rows  u_c_sr (.state_in(ciph_sb),  .state_out(ciph_sr));
    minisoc_aes_mix_columns u_c_mc (.state_in(ciph_sr),  .state_out(ciph_mc));

    // Mux da rodada final: round_cnt == 9 → pula MixColumns
    assign ciph_pre_ark = is_final ? ciph_sr : ciph_mc;

    minisoc_aes_add_round_key u_c_ark (
        .state_in  (ciph_pre_ark),
        .round_key (round_key),
        .state_out (ciph_final)
    );

    // =========================================================================
    // InvCipher path (FIPS-197 5.3.5)
    //
    //   InvShiftRows(state_in) → InvSubBytes → AddRoundKey(rk) → [InvMixColumns]
    //
    // IMPORTANTE: a ordem é DIFERENTE do Cipher — AddRoundKey vem ANTES de
    // InvMixColumns. Na rodada final (round_cnt == 9), InvMixColumns é pulado,
    // de modo que AddRoundKey é a última operação (FIPS-197 5.3.5).
    // =========================================================================
    logic [127:0] inv_sr;       // InvShiftRows(state_in)
    logic [127:0] inv_sb;       // InvSubBytes(inv_sr)
    logic [127:0] inv_ark;      // AddRoundKey(inv_sb, round_key)
    logic [127:0] inv_mc;       // InvMixColumns(inv_ark)
    logic [127:0] inv_final;    // Mux da rodada final (com/sem InvMixColumns)

    minisoc_aes_inv_shift_rows  u_i_sr (.state_in(state_in), .state_out(inv_sr));
    minisoc_aes_inv_sub_bytes   u_i_sb (.state_in(inv_sr),   .state_out(inv_sb));

    minisoc_aes_add_round_key   u_i_ark (
        .state_in  (inv_sb),
        .round_key (round_key),
        .state_out (inv_ark)
    );

    minisoc_aes_inv_mix_columns u_i_mc (.state_in(inv_ark),  .state_out(inv_mc));

    // Mux da rodada final: round_cnt == 9 → pula InvMixColumns
    assign inv_final = is_final ? inv_ark : inv_mc;

    // =========================================================================
    // Mux final (3.3): depois das duas cadeias completas.
    // As duas cadeias rodam em paralelo a partir de state_in — SubBytes e
    // ShiftRows não estão no caminho crítico do mux de seleção.
    // =========================================================================
    assign state_out = use_inv ? inv_final : ciph_final;

endmodule