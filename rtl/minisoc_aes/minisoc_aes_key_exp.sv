// =============================================================================
// minisoc_aes_key_exp.sv
//
// AES-128 Key Expansion — 11 round keys (44 words) em banco de FFs.
// Conforme Issue #1 e Microarquitetura v1.2 §10.
//
// Interface com minisoc_aes_top (§10.4):
//   - start       : pulso de 1 ciclo em sys_clk, dispara a expansão.
//   - key_in      : cfg_key (128 bits, quasi-estático durante start).
//   - round_idx   : 0..10 (selecionado pela FSM §9.5).
//   - round_key   : mux 11:1 combinacional — sem latência adicional.
//   - ready       : sobe exatamente 10 ciclos após start; sticky até
//                   novo start (idempotência em ST_KEY_DONE).
//
// Contrato com a FSM (§9.4/§9.5):
//   ST_FETCH_3      : round_idx = 0  (cipher)   → rk[0]
//                     round_idx = 10 (InvCipher)→ rk[10]
//   ST_EXECUTE      : round_idx = cnt+1 (cipher)       → rk[1..10]
//                     round_idx = 9-cnt (InvCipher)    → rk[9..0]
//
// Algoritmo (FIPS-197 §5.2):
//   rk_bank[0] = key_in
//   w[i]   = w[i-4] ^ SubWord(RotWord(w[i-1])) ^ Rcon[i/4]
//   w[i+1] = w[i-3] ^ w[i]
//   w[i+2] = w[i-2] ^ w[i+1]
//   w[i+3] = w[i-1] ^ w[i+2]
//   rk_bank[r] = { w[4r], w[4r+1], w[4r+2], w[4r+3] }
//
// Decisões de projeto (§10.8):
//   - Sem memória compartilhada (1408 FFs internos).
//   - 4 S-boxes dedicadas em paralelo (não reusa as do datapath).
//   - Leitura de rk_bank via mux 11:1 combinacional.
//   - Sem escrita parcial: os 11 round keys são sempre regravados.
//   - rk_bank e w_prev NÃO têm reset (custo de 1408+128 FFs).
//     ready=0 em reset garante que valores inválidos nunca são lidos.
// =============================================================================

module minisoc_aes_key_exp (
    input  logic          clk,        // sys_clk
    input  logic          rst_n,      // sys_rst_n (ativo baixo, assíncrono)
    input  logic          start,      // pulso de 1 ciclo
    input  logic [127:0]  key_in,     // cfg_key
    input  logic [3:0]    round_idx,  // 0..10 (selecionado pela FSM)
    output logic [127:0]  round_key,  // rk[round_idx] (combinacional)
    output logic          ready       // 1 quando rk_bank[0..10] válidos
);

    // -------------------------------------------------------------------------
    // FSM interna (§10.6)
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_KEY_IDLE = 2'b00,   // aguarda start; ready=0
        ST_KEY_RUN  = 2'b01,   // computa rk[cnt], cnt=2..10
        ST_KEY_DONE = 2'b10    // ready=1; idempotente em novo start
    } key_exp_state_t;

    key_exp_state_t state;

    // -------------------------------------------------------------------------
    // Registradores (§10.5)
    // -------------------------------------------------------------------------
    logic [127:0] rk_bank [0:10];  // 11 round keys × 128 bits = 1408 FFs
    logic [127:0] w_prev;          // últimas 4 words (w[i-4..i-1])
    logic [7:0]   rcon;            // Rcon corrente (0x01..0x36)
    logic [3:0]   cnt;             // índice do round key a ser produzido (2..10)

    // -------------------------------------------------------------------------
    // xtime: multiplicação por {02} em GF(2^8) — usado no encadeamento de Rcon
    // -------------------------------------------------------------------------
    function automatic logic [7:0] xtime(input logic [7:0] b);
        return b[7] ? ((b << 1) ^ 8'h1B) : (b << 1);
    endfunction

    // -------------------------------------------------------------------------
    // Muxes de entrada da iteração corrente
    //
    // Nos ciclos de START (IDLE ou DONE com start=1) a primeira iteração é
    // feita diretamente sobre key_in. Isso permite que rk[1] esteja pronto já
    // no fim do ciclo de START, garantindo que ready suba exatamente 10 ciclos
    // após o pulso (ver truque de timing no comentário do módulo).
    //
    // Nos ciclos de RUN, w_prev contém {w[i-4..i-1]} e rcon o Rcon corrente.
    // -------------------------------------------------------------------------
    wire in_first_iter = (state != ST_KEY_RUN);

    wire [127:0] cur_words  = in_first_iter ? key_in : w_prev;
    wire [7:0]   rcon_active = in_first_iter ? 8'h01  : rcon;

    // Decomposição nas 4 words de 32 bits
    wire [31:0] cw0 = cur_words[127:96];
    wire [31:0] cw1 = cur_words[ 95:64];
    wire [31:0] cw2 = cur_words[ 63:32];
    wire [31:0] cw3 = cur_words[ 31: 0];

    // -------------------------------------------------------------------------
    // RotWord(cw3): rotação de 1 byte à esquerda
    // -------------------------------------------------------------------------
    wire [31:0] rot_cw3 = {cw3[23:0], cw3[31:24]};

    // -------------------------------------------------------------------------
    // SubWord via 4 S-boxes dedicadas em paralelo (§10.8.2)
    // Não reusa as S-boxes do datapath — evita mux no caminho crítico
    // do SubBytes.
    // -------------------------------------------------------------------------
    wire [7:0] sb0, sb1, sb2, sb3;
    minisoc_aes_sbox u_kexp_sbox_0 (.in(rot_cw3[31:24]), .out(sb0));
    minisoc_aes_sbox u_kexp_sbox_1 (.in(rot_cw3[23:16]), .out(sb1));
    minisoc_aes_sbox u_kexp_sbox_2 (.in(rot_cw3[15: 8]), .out(sb2));
    minisoc_aes_sbox u_kexp_sbox_3 (.in(rot_cw3[ 7: 0]), .out(sb3));

    wire [31:0] sub_word = {sb0, sb1, sb2, sb3};

    // Rcon aplicado ao byte mais significativo da word (FIPS-197 §5.2)
    wire [31:0] rcon_word = {rcon_active, 24'h00_0000};

    // -------------------------------------------------------------------------
    // Nova round key (4 words), FIPS-197 §5.2
    // -------------------------------------------------------------------------
    wire [31:0] nw0 = cw0 ^ sub_word ^ rcon_word;
    wire [31:0] nw1 = cw1 ^ nw0;
    wire [31:0] nw2 = cw2 ^ nw1;
    wire [31:0] nw3 = cw3 ^ nw2;

    wire [127:0] new_rk = {nw0, nw1, nw2, nw3};

    // -------------------------------------------------------------------------
    // Lógica sequencial
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_KEY_IDLE;
            cnt   <= 4'd0;
            rcon  <= 8'h01;              // Rcon[1] no reset
            // rk_bank e w_prev ficam sem reset (estado indeterminado),
            // conforme §10.8.5. ready=0 em IDLE garante que nunca são lidos.
        end else begin
            case (state)

                // ---------------------------------------------------------
                // ST_KEY_IDLE: aguarda start. No pulso, executa a 1ª
                // iteração diretamente sobre key_in (ver muxes acima),
                // carregando rk[0] e rk[1] no mesmo ciclo.
                // ---------------------------------------------------------
                ST_KEY_IDLE: begin
                    if (start) begin
                        rk_bank[0] <= key_in;              // rk[0] = K
                        rk_bank[1] <= new_rk;              // rk[1] (comb. de key_in)
                        w_prev     <= new_rk;
                        rcon       <= xtime(rcon_active);  // 0x02
                        cnt        <= 4'd2;
                        state      <= ST_KEY_RUN;
                    end
                end

                // ---------------------------------------------------------
                // ST_KEY_RUN: uma iteração por ciclo, produzindo rk[cnt].
                // cnt=2..10 → 9 ciclos. Somados ao ciclo de start, fecham
                // os 10 ciclos de latência exigidos.
                // ---------------------------------------------------------
                ST_KEY_RUN: begin
                    rk_bank[cnt] <= new_rk;
                    w_prev       <= new_rk;
                    rcon         <= xtime(rcon_active);
                    if (cnt == 4'd10) begin
                        state <= ST_KEY_DONE;             // rk[10] gravado
                    end else begin
                        cnt   <= cnt + 4'd1;
                    end
                end

                // ---------------------------------------------------------
                // ST_KEY_DONE: ready=1 (combinacional). Idempotente:
                // novo start regenera o banco do zero (§10.8.4).
                // ---------------------------------------------------------
                ST_KEY_DONE: begin
                    if (start) begin
                        rk_bank[0] <= key_in;
                        rk_bank[1] <= new_rk;              // recomp. de key_in
                        w_prev     <= new_rk;
                        rcon       <= xtime(rcon_active);  // 0x02
                        cnt        <= 4'd2;
                        state      <= ST_KEY_RUN;
                    end
                end

                default: state <= ST_KEY_IDLE;

            endcase
        end
    end

    // -------------------------------------------------------------------------
    // round_key: mux 11:1 combinacional (§10.4)
    //
    // Sem latência: a FSM apresenta round_idx e lê o valor no mesmo ciclo.
    // round_idx ∈ {0..10}; valores 11..15 são protegidos por default.
    // -------------------------------------------------------------------------
    always_comb begin
        case (round_idx)
            4'd0 :   round_key = rk_bank[0];
            4'd1 :   round_key = rk_bank[1];
            4'd2 :   round_key = rk_bank[2];
            4'd3 :   round_key = rk_bank[3];
            4'd4 :   round_key = rk_bank[4];
            4'd5 :   round_key = rk_bank[5];
            4'd6 :   round_key = rk_bank[6];
            4'd7 :   round_key = rk_bank[7];
            4'd8 :   round_key = rk_bank[8];
            4'd9 :   round_key = rk_bank[9];
            4'd10:   round_key = rk_bank[10];
            default: round_key = rk_bank[0];           // proteção (não deve ocorrer)
        endcase
    end

    // -------------------------------------------------------------------------
    // ready: combinacional a partir do estado
    //
    // Deve subir 10 ciclos após start e permanecer sticky até novo start.
    // Como ready=1 só em ST_KEY_DONE, e este estado é atingido no fim do
    // 10º ciclo pós-start, ready=1 é observado pelo FSM externo exatamente
    // 10 ciclos após o pulso (ver diagrama no cabeçalho).
    // -------------------------------------------------------------------------
    assign ready = (state == ST_KEY_DONE);

endmodule