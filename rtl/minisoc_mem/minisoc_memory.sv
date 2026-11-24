// =============================================================================
// minisoc_memory.sv
//
// Memória compartilhada do MiniSoC AES (Block Guide §7).
//
// Organização : 1024 palavras × 32 bits (4 KiB)
// Porta       : única, síncrona, single-port
// Reset       : sem reset funcional — o conteúdo NÃO é apagado pelo reset
//               global; o estado inicial do array é indeterminado (§7.3).
//
// Ownership (MEM_SEL_AES — §7.2):
//   mem_sel_aes = 0 : clock, endereço, write-data e write-enable vêm da
//                     interface externa MEMORY DATA
//                     (mem_clk, mem_i_addr, mem_i_data, mem_i_wr_en).
//   mem_sel_aes = 1 : clock, endereço, write-data e write-enable vêm do
//                     AES engine
//                     (aes_clk, aes_addr, aes_wdata, aes_wr_en).
//
// Semântica:
//   - Escrita síncrona: mem[addr] <= wdata na borda de subida do clock
//     selecionado quando wr_en = 1.
//   - Leitura síncrona: read data registrado (1 ciclo de latência),
//     atualizado apenas quando wr_en = 0 (sem alteração durante escrita).
//   - Exclusão mútua é contratual: apenas um mestre acessa por vez. A troca
//     de ownership é responsabilidade do firmware e deve ocorrer com o AES
//     ocioso e sem acesso externo em andamento.
// =============================================================================

`default_nettype none

module minisoc_memory (
    // ----- Interface externa MEMORY DATA (§3) ------------------------------
    input  logic        mem_clk,       // até 200 MHz
    input  logic [31:0] mem_i_data,
    input  logic        mem_i_wr_en,   // 1 = write, 0 = read
    input  logic [9:0]  mem_i_addr,    // 0..1023
    output logic [31:0] mem_o_data,

    // ----- Interface do AES engine (§7.2) ----------------------------------
    input  logic        aes_clk,       // sys_clk do PLL
    input  logic [9:0]  aes_addr,
    input  logic [31:0] aes_wdata,
    input  logic        aes_wr_en,
    output logic [31:0] aes_rdata,

    // ----- Ownership -------------------------------------------------------
    input  logic        mem_sel_aes    // 0 = MEMORY DATA, 1 = AES
);

    // -------------------------------------------------------------------------
    // Array 1024 × 32 — sem reset (§7.3)
    // -------------------------------------------------------------------------
    logic [31:0] mem [0:1023];

    // -------------------------------------------------------------------------
    // Muxes de ownership — selecionam o mestre ativo
    // -------------------------------------------------------------------------
    logic        mux_clk;
    logic [9:0]  mux_addr;
    logic [31:0] mux_wdata;
    logic        mux_wr_en;

    always_comb begin
        if (mem_sel_aes) begin
            mux_clk   = aes_clk;
            mux_addr  = aes_addr;
            mux_wdata = aes_wdata;
            mux_wr_en = aes_wr_en;
        end else begin
            mux_clk   = mem_clk;
            mux_addr  = mem_i_addr;
            mux_wdata = mem_i_data;
            mux_wr_en = mem_i_wr_en;
        end
    end

    // -------------------------------------------------------------------------
    // Porta única síncrona
    // -------------------------------------------------------------------------
    logic [31:0] rdata_q;

    always_ff @(posedge mux_clk) begin
        if (mux_wr_en) begin
            mem[mux_addr] <= mux_wdata;
        end else begin
            rdata_q <= mem[mux_addr];
        end
    end

    // -------------------------------------------------------------------------
    // Saídas — o dono corrente é quem consome a sua saída. Não há
    // mux adicional aqui: ambos os lados veem rdata_q; o contrato de
    // ownership garante que não há leitura concorrente (§7.2).
    // -------------------------------------------------------------------------
    assign mem_o_data = rdata_q;
    assign aes_rdata  = rdata_q;

endmodule

`default_nettype wire