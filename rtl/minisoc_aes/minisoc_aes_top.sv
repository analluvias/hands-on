// =============================================================================
// minisoc_aes_top.sv
//
// Controlador do AES engine + interface de memória (Block Guide §8).
//
// Integra:
//   - minisoc_aes_key_exp (expansão AES-128, 11 round keys)
//   - minisoc_aes_dp      (datapath uma rodada/ciclo, cipher + inv cipher)
//
// Modos implementados (nesta milestone): ECB (000), CBC (001), CTR (101).
//   - Encrypt e decrypt para ECB/CBC.
//   - CTR: primitive SEMPRE encrypt (§8.2); DECRYPT é ignorado para o AES.
//
// Modos NÃO implementados (milestone atual):
//   - PCBC (010), CFB (011), OFB (100): reservados para Semana 10.
//   - Reservados (110, 111).
//   Configurar qualquer um destes produz ERROR e encerra sem processar.
//
// Contrato com o datapath (ver cabeçalho minisoc_aes_dp.sv):
//   - state_in já inclui XOR de chaining + round key inicial.
//   - round_idx = round_cnt + 1 (cipher) ou 9 - round_cnt (inv_cipher).
//   - rk inicial = rk[0] (cipher) ou rk[10] (InvCipher), aplicado no FSM.
//
// Fluxo (por bloco, in-place):
//   FETCH_0..4 → ROUNDS×10 → WRITE_0..3
//   4 palavras lidas, 128 bits processados, 4 palavras escritas na mesma base.
//
// Timing de memória: 1 ciclo de leitura (word i apresentada em FETCH_i, lida
// em FETCH_{i+1}). 4 palavras ⇒ 5 ciclos de FETCH; o último (FETCH_4)
// combina captura de word 3 + cálculo de state_in + entrada em ROUNDS.
//
// Ownership: o AES NÃO altera MEM_SEL_AES. Pressupõe que o firmware já
// entregou a memória ao AES antes de START e a devolve após DONE (§7.2/§9).
// =============================================================================

`default_nettype none

module minisoc_aes_top (
    input  logic         clk,            // sys_clk (PLL locked)
    input  logic         rst_n,          // async, ativo baixo

    // ----- Configuração vinda do SPI (quasi-estática) ----------------------
    input  logic [127:0] cfg_key,
    input  logic [127:0] cfg_iv,
    input  logic [63:0]  cfg_counter,
    input  logic [8:0]   cfg_num_blocks,
    input  logic [2:0]   cfg_mode,
    input  logic         cfg_decrypt,
    input  logic         cmd_start,      // pulso de 1 ciclo

    // ----- Status para o SPI ----------------------------------------------
    output logic         status_busy,
    output logic         status_done,    // sticky
    output logic         status_error,   // sticky
    output logic [8:0]   status_blocks_done,

    // ----- Interface de memória (lado AES) --------------------------------
    output logic [9:0]   mem_addr,
    output logic [31:0]  mem_wdata,
    output logic         mem_wr_en,
    input  logic [31:0]  mem_rdata
);

    // -------------------------------------------------------------------------
    // Captura de configuração (no START)
    // -------------------------------------------------------------------------
    logic [127:0] c_key;
    logic [127:0] c_iv;
    logic [63:0]  c_counter;
    logic [8:0]   c_num_blocks;
    logic [2:0]   c_mode;
    logic         c_decrypt;

    // -------------------------------------------------------------------------
    // Chaining / CTR
    // -------------------------------------------------------------------------
    logic [127:0] chain_reg;             // IV (CBC block 0) / prev ciphertext
    logic [63:0]  ctr_reg;               // contador de 64 bits (§8.2 CTR)

    // -------------------------------------------------------------------------
    // Tracking de bloco
    // -------------------------------------------------------------------------
    logic [8:0]   block_idx;             // 0 .. num_blocks-1
    logic [8:0]   blocks_done_q;

    // -------------------------------------------------------------------------
    // Palavras lidas da memória (word0 = MSB, §7.1)
    // -------------------------------------------------------------------------
    logic [31:0]  q0, q1, q2, q3;
    wire  [127:0] fetched_data      = {q0, q1, q2, q3};
    wire  [127:0] fetched_data_next = {q0, q1, q2, mem_rdata}; // durante FETCH_4

    // -------------------------------------------------------------------------
    // Estado do datapath
    // -------------------------------------------------------------------------
    logic [127:0] state_reg;
    logic [3:0]   round_cnt;
    logic [3:0]   dp_round_idx;
    wire  [127:0] dp_round_key;
    wire  [127:0] dp_out;

    // -------------------------------------------------------------------------
    // Key expansion
    // -------------------------------------------------------------------------
    logic         key_start;
    logic         key_ready;

    // -------------------------------------------------------------------------
    // Sub-counters
    // -------------------------------------------------------------------------
    logic [2:0]   fetch_cnt;             // 0..4
    logic [1:0]   write_cnt;             // 0..3

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_VALIDATE,
        ST_KEY_START,     // pulso de 1 ciclo em key_start
        ST_KEY_WAIT,      // aguarda key_exp.ready
        ST_FETCH,         // 5 ciclos: 4 palavras + state_in
        ST_ROUNDS,        // 10 ciclos
        ST_WRITE          // 4 ciclos
    } state_t;

    state_t state;

    // -------------------------------------------------------------------------
    // Sticky flags
    // -------------------------------------------------------------------------
    logic done_q, error_q;

    // -------------------------------------------------------------------------
    // Derivados
    // -------------------------------------------------------------------------
    // use_inv alinhado com minisoc_aes_dp::use_inv (para escolher round_idx).
    wire use_inv = c_decrypt && (c_mode != 3'b101);

    // Validação: NUM_BLOCKS ∈ [1,256]; MODE ∈ {0,1,5}.
    wire cfg_valid = (c_num_blocks != 9'd0)
                  && (c_num_blocks <= 9'd256)
                  && ((c_mode == 3'b000) || (c_mode == 3'b001) || (c_mode == 3'b101));

    // -------------------------------------------------------------------------
    // Entrada do AES primitive (pré-round-key)
    //   ECB enc/dec, CBC dec, CTR: usa dados do bloco (CTR usa IV^counter)
    //   CBC enc                  : plaintext ^ chaining
    // -------------------------------------------------------------------------
    wire [127:0] ctr_iv_xor = c_iv ^ {64'h0, ctr_reg};

    wire [127:0] aes_input_pre_rk;
    assign aes_input_pre_rk = (c_mode == 3'b101)                    ? ctr_iv_xor
                            : (c_mode == 3'b001 && !use_inv)        ? (fetched_data_next ^ chain_reg)
                            :                                          fetched_data_next;

    // Estado inicial do AES (com round key inicial aplicada pelo FSM).
    wire [127:0] state_in_initial = aes_input_pre_rk ^ dp_round_key;

    // -------------------------------------------------------------------------
    // Dados finais do bloco (escrita in-place)
    //   ECB / CBC enc: state_reg (ciphertext ou plaintext recuperado)
    //   CBC dec      : state_reg ^ chaining (prev ciphertext / IV)
    //   CTR          : fetched_data ^ keystream
    // -------------------------------------------------------------------------
    wire [127:0] final_data = (c_mode == 3'b101)                    ? (fetched_data ^ state_reg)
                            : (c_mode == 3'b001 && use_inv)         ? (state_reg ^ chain_reg)
                            :                                          state_reg;

    // -------------------------------------------------------------------------
    // Base de endereço do bloco corrente (4 palavras por bloco, §7.1)
    // -------------------------------------------------------------------------
    wire [9:0] block_base = {block_idx[7:0], 2'b00};

    // =========================================================================
    // Sub-módulos
    // =========================================================================
    minisoc_aes_key_exp u_key_exp (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (key_start),
        .key_in    (c_key),
        .round_idx (dp_round_idx),
        .round_key (dp_round_key),
        .ready     (key_ready)
    );

    minisoc_aes_dp u_dp (
        .state_in  (state_reg),
        .round_cnt (round_cnt),
        .round_key (dp_round_key),
        .mode      (c_mode),
        .decrypt   (c_decrypt),
        .state_out (dp_out)
    );

    // =========================================================================
    // Seleção de round_idx
    //   FETCH_4 : rk inicial (cipher: rk[0], inv: rk[10])
    //   ROUNDS  : rk[1..10] (cipher) ou rk[9..0] (inv)
    // =========================================================================
    always_comb begin
        if (state == ST_FETCH && fetch_cnt == 3'd4)
            dp_round_idx = use_inv ? 4'd10 : 4'd0;
        else if (state == ST_ROUNDS)
            dp_round_idx = use_inv ? (4'd9 - round_cnt) : (round_cnt + 4'd1);
        else
            dp_round_idx = 4'd0;
    end

    // =========================================================================
    // Interface de memória (combinacional)
    // =========================================================================
    always_comb begin
        mem_addr  = 10'd0;
        mem_wdata = 32'd0;
        mem_wr_en = 1'b0;

        case (state)
            ST_FETCH: begin
                // 5 ciclos: 4 palavras (0..3) + 1 de preparação
                mem_addr  = block_base + {7'd0, fetch_cnt};
                mem_wr_en = 1'b0;
            end
            ST_WRITE: begin
                mem_addr  = block_base + {8'd0, write_cnt};
                mem_wr_en = 1'b1;
                case (write_cnt)
                    2'd0: mem_wdata = final_data[127:96];
                    2'd1: mem_wdata = final_data[95:64];
                    2'd2: mem_wdata = final_data[63:32];
                    2'd3: mem_wdata = final_data[31:0];
                endcase
            end
            default: begin
                mem_addr  = 10'd0;
                mem_wdata = 32'd0;
                mem_wr_en = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // FSM principal
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            c_key         <= 128'd0;
            c_iv          <= 128'd0;
            c_counter     <= 64'd0;
            c_num_blocks  <= 9'd0;
            c_mode        <= 3'd0;
            c_decrypt     <= 1'b0;
            chain_reg     <= 128'd0;
            ctr_reg       <= 64'd0;
            block_idx     <= 9'd0;
            blocks_done_q <= 9'd0;
            q0            <= 32'd0;
            q1            <= 32'd0;
            q2            <= 32'd0;
            q3            <= 32'd0;
            state_reg     <= 128'd0;
            round_cnt     <= 4'd0;
            fetch_cnt     <= 3'd0;
            write_cnt     <= 2'd0;
            key_start     <= 1'b0;
            done_q        <= 1'b0;
            error_q       <= 1'b0;
        end else begin
            // Default: key_start é pulso de 1 ciclo.
            key_start <= 1'b0;

            case (state)
                // -------------------------------------------------------------
                ST_IDLE: begin
                    if (cmd_start) begin
                        // Captura config + limpa flags sticky (novo START).
                        c_key         <= cfg_key;
                        c_iv          <= cfg_iv;
                        c_counter     <= cfg_counter;
                        c_num_blocks  <= cfg_num_blocks;
                        c_mode        <= cfg_mode;
                        c_decrypt     <= cfg_decrypt;
                        done_q        <= 1'b0;
                        error_q       <= 1'b0;
                        state         <= ST_VALIDATE;
                    end
                end

                // -------------------------------------------------------------
                ST_VALIDATE: begin
                    blocks_done_q <= 9'd0;
                    if (cfg_valid) begin
                        chain_reg <= c_iv;
                        ctr_reg   <= c_counter;
                        block_idx <= 9'd0;
                        key_start <= 1'b1;
                        state     <= ST_KEY_START;
                    end else begin
                        error_q   <= 1'b1;
                        state     <= ST_IDLE;
                    end
                end

                // -------------------------------------------------------------
                ST_KEY_START: begin
                    // key_start foi pulsado no ciclo anterior.
                    // Este estado garante que o key_ready "sticky" de uma
                    // operação anterior não seja confundido com o desta.
                    state <= ST_KEY_WAIT;
                end

                // -------------------------------------------------------------
                ST_KEY_WAIT: begin
                    if (key_ready) begin
                        fetch_cnt <= 3'd0;
                        state     <= ST_FETCH;
                    end
                end

                // -------------------------------------------------------------
                ST_FETCH: begin
                    case (fetch_cnt)
                        3'd0: fetch_cnt <= 3'd1;
                        3'd1: begin q0 <= mem_rdata; fetch_cnt <= 3'd2; end
                        3'd2: begin q1 <= mem_rdata; fetch_cnt <= 3'd3; end
                        3'd3: begin q2 <= mem_rdata; fetch_cnt <= 3'd4; end
                        3'd4: begin
                            // Última palavra + state_in (inclui rk inicial e chaining).
                            q3        <= mem_rdata;
                            state_reg <= state_in_initial;
                            round_cnt <= 4'd0;
                            state     <= ST_ROUNDS;
                        end
                        default: fetch_cnt <= 3'd0;
                    endcase
                end

                // -------------------------------------------------------------
                ST_ROUNDS: begin
                    state_reg <= dp_out;
                    if (round_cnt == 4'd9) begin
                        write_cnt <= 2'd0;
                        state     <= ST_WRITE;
                    end else begin
                        round_cnt <= round_cnt + 4'd1;
                    end
                end

                // -------------------------------------------------------------
                ST_WRITE: begin
                    if (write_cnt == 2'd3) begin
                        // Última palavra escrita. Atualiza chaining / CTR.
                        if (c_mode == 3'b001) begin
                            // CBC: enc → próximo chain = ciphertext (output);
                            //      dec → próximo chain = ciphertext (input).
                            chain_reg <= use_inv ? fetched_data : state_reg;
                        end else if (c_mode == 3'b101) begin
                            // CTR: incrementa contador de 64 bits.
                            ctr_reg <= ctr_reg + 64'd1;
                        end

                        blocks_done_q <= block_idx + 9'd1;

                        if ((block_idx + 9'd1) == c_num_blocks) begin
                            done_q <= 1'b1;
                            state  <= ST_IDLE;
                        end else begin
                            block_idx <= block_idx + 9'd1;
                            fetch_cnt <= 3'd0;
                            state     <= ST_FETCH;
                        end
                    end else begin
                        write_cnt <= write_cnt + 2'd1;
                    end
                end

                // -------------------------------------------------------------
                default: state <= ST_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Status outputs
    // =========================================================================
    assign status_busy        = (state != ST_IDLE);
    assign status_done        = done_q;
    assign status_error       = error_q;
    assign status_blocks_done = blocks_done_q;

endmodule

`default_nettype wire