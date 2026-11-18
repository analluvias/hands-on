// =============================================================================
// minisoc_pll_mock.sv
//
// Modelo de INTEGRAÇÃO do PLL para o MiniSoC AES (Block Guide §4.1).
//
//   não é um modelo físico:
//   - Sem jitter, sem ruído, sem estabilização analógica.
//   - Tempo de lock é um contador determinístico de ciclos de clk.
//   - sys_clk é uma versão dividida de clk, gated por pll_locked.
//
// Interface:
//   Entradas : clk (referência nominal 2 GHz), rst_n, pll_enable, pll_div_sel[1:0]
//   Saídas   : pll_locked, sys_clk
//
// Divider:
//   pll_div_sel = 2'b00 -> sys_clk = clk        (÷1)
//   pll_div_sel = 2'b01 -> sys_clk = clk / 2    (÷2)
//   pll_div_sel = 2'b10 -> sys_clk = clk / 4    (÷4)
//   pll_div_sel = 2'b11 -> sys_clk = clk / 8    (÷8)
//
// Comportamento:
//   - Reset síncrono em clk (rst_n ativo baixo).
//   - Após pll_enable=1, pll_locked sobe depois de LOCK_CYCLES ciclos de clk.
//   - Se pll_enable cair, pll_locked volta a 0 e o contador reinicia.
//   - sys_clk = 0 enquanto pll_locked = 0.
//   - Mudança em pll_div_sel NÃO provoca re-lock (assume-se configurado
//     antes do primeiro pll_enable=1, como no fluxo do SoC).
// =============================================================================

module minisoc_pll_mock #(
    parameter int LOCK_CYCLES = 16
) (
    input  logic       clk,          // referência (nominal 2 GHz)
    input  logic       rst_n,        // reset síncrono (ativo baixo)
    input  logic       pll_enable,
    input  logic [1:0] pll_div_sel,  // 00=÷1, 01=÷2, 10=÷4, 11=÷8
    output logic       pll_locked,
    output logic       sys_clk
);

    // -------------------------------------------------------------------------
    // Contador de lock
    // -------------------------------------------------------------------------
    localparam int                 LOCK_W = $clog2(LOCK_CYCLES + 1);
    localparam logic [LOCK_W-1:0] LOCK_TARGET = LOCK_CYCLES - 1;

    logic [LOCK_W-1:0] lock_cnt;
    logic              locked_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            lock_cnt <= '0;
            locked_q <= 1'b0;
        end else if (!pll_enable) begin
            lock_cnt <= '0;
            locked_q <= 1'b0;
        end else if (lock_cnt == LOCK_TARGET) begin
            locked_q <= 1'b1;
        end else begin
            lock_cnt <= lock_cnt + 1'b1;
        end
    end

    assign pll_locked = locked_q;

    // -------------------------------------------------------------------------
    // Divisor programável
    //
    // half_period = ciclos de clk entre toggles de div_clk:
    //   ÷1 -> bypass (half_period irrelevante)
    //   ÷2 -> 1
    //   ÷4 -> 2
    //   ÷8 -> 4
    // -------------------------------------------------------------------------
    logic [2:0] div_cnt;
    logic       div_clk;

    logic [2:0] half_period;
    always_comb begin
        case (pll_div_sel)
            2'b00:   half_period = 3'd0;  // bypass
            2'b01:   half_period = 3'd1;  // ÷2
            2'b10:   half_period = 3'd2;  // ÷4
            2'b11:   half_period = 3'd4;  // ÷8
            default: half_period = 3'd0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            div_cnt <= 3'd0;
            div_clk <= 1'b0;
        end else if (!pll_enable) begin
            div_cnt <= 3'd0;
            div_clk <= 1'b0;
        end else if (pll_div_sel == 2'b00) begin
            div_cnt <= 3'd0;
            div_clk <= 1'b0;
        end else if (div_cnt >= half_period) begin
            // proteção contra troca de pll_div_sel em runtime
            div_cnt <= 3'd0;
        end else if (div_cnt == (half_period - 3'd1)) begin
            div_cnt <= 3'd0;
            div_clk <= ~div_clk;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    // Bypass combinacional em ÷1; senão usa div_clk
    wire sys_clk_int = (pll_div_sel == 2'b00) ? clk : div_clk;

    // -------------------------------------------------------------------------
    // Gating: sys_clk só oscila quando locked_q = 1
    // -------------------------------------------------------------------------
    assign sys_clk = locked_q & sys_clk_int;

endmodule