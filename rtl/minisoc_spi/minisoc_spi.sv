// =============================================================================
// minisoc_spi.sv
//
// Integração top do SPI Front-End (Issue 5).
//
// Instancia:
//   - minisoc_spi_rx   : receptor serial no domínio spi_sclk (§5.3)
//   - minisoc_spi_core : CDC + decode + register bank no domínio clk (§5.4)
//   - minisoc_spi_tx   : transmissor MISO no domínio spi_sclk (§5.5)
//
// Interface externa (Block Guide §3):
//   SPI IF        : spi_sclk, spi_cs_n, spi_mosi, spi_miso
//   CLK           : clk (domínio always-on)
//   RESET         : rst_n (async, ativo baixo)
//   Entradas AES  : status_busy, status_done, status_error,
//                   status_blocks_done[8:0]
//   Entrada PLL   : pll_locked
//   Saídas AES    : cfg_key[127:0], cfg_iv[127:0], cfg_counter[63:0],
//                   cfg_num_blocks[8:0], cfg_mode[2:0], cfg_decrypt, cmd_start
//   Debug         : version_dbg[31:0] (= 32'h0000_0001, espelha VERSION 0x0D)
//
// CDC (justificativas):
//   - spi_sclk → clk : frame_valid_toggle (evento) + frame_data (quasi-estático).
//                     Sincronizado pelo u_core via 2FF + edge detect (§4.2).
//   - clk → spi_sclk : read_data (quasi-estático).
//                     Consumido pelo u_tx via negedge spi_cs_n (§4.1/§5.4).
//
// Reset:
//   rst_n é async global, passado direto para os 3 sub-blocos. A sincronização
//   de reset (reset synchronizer de 2FF, §3) é responsabilidade do minisoc_top,
//   NÃO deste módulo.
//
// Nota sobre version_dbg:
//   O valor 0x0000_0001 é fixado no minisoc_spi_core (case de leitura em 0x0D).
//   version_dbg duplica essa constante para conveniência do TB em waveform.
//   Se mudar VERSION, atualizar aqui E no core (§6, linha 0x0D).
// =============================================================================

module minisoc_spi (
    // --- SPI IF (§3) ------------------------------------------------------
    input  logic         spi_sclk,
    input  logic         spi_cs_n,
    input  logic         spi_mosi,
    output logic         spi_miso,

    // --- CLK / RESET ------------------------------------------------------
    input  logic         clk,
    input  logic         rst_n,

    // --- Status do AES / PLL (entradas) -----------------------------------
    input  logic         status_busy,
    input  logic         status_done,
    input  logic         status_error,
    input  logic [8:0]   status_blocks_done,
    input  logic         pll_locked,

    // --- Config para o AES (saídas) ---------------------------------------
    output logic [127:0] cfg_key,
    output logic [127:0] cfg_iv,
    output logic [63:0]  cfg_counter,
    output logic [8:0]   cfg_num_blocks,
    output logic [2:0]   cfg_mode,
    output logic         cfg_decrypt,
    output logic         cmd_start,

    // --- Debug ------------------------------------------------------------
    output logic [31:0]  version_dbg
);

    // -------------------------------------------------------------------------
    // Internos entre RX e Core
    // -------------------------------------------------------------------------
    logic [39:0] frame_data;
    logic        frame_valid_toggle;

    // -------------------------------------------------------------------------
    // Internos entre Core e TX
    // -------------------------------------------------------------------------
    logic [31:0] read_data;

    // -------------------------------------------------------------------------
    // RX: receptor serial no domínio spi_sclk
    // -------------------------------------------------------------------------
    minisoc_spi_rx u_rx (
        .spi_sclk           (spi_sclk),
        .spi_cs_n           (spi_cs_n),
        .spi_mosi           (spi_mosi),
        .rst_n              (rst_n),
        .frame_data         (frame_data),
        .frame_valid_toggle (frame_valid_toggle)
    );

    // -------------------------------------------------------------------------
    // Core: CDC + decode + register bank no domínio clk
    // -------------------------------------------------------------------------
    minisoc_spi_core u_core (
        .clk                 (clk),
        .rst_n               (rst_n),
        .frame_data          (frame_data),
        .frame_valid_toggle  (frame_valid_toggle),
        .status_busy         (status_busy),
        .status_done         (status_done),
        .status_error        (status_error),
        .status_blocks_done  (status_blocks_done),
        .pll_locked          (pll_locked),
        .cfg_key             (cfg_key),
        .cfg_iv              (cfg_iv),
        .cfg_counter         (cfg_counter),
        .cfg_num_blocks      (cfg_num_blocks),
        .cfg_mode            (cfg_mode),
        .cfg_decrypt         (cfg_decrypt),
        .cmd_start           (cmd_start),
        .read_data           (read_data)
    );

    // -------------------------------------------------------------------------
    // TX: transmissor MISO no domínio spi_sclk
    // -------------------------------------------------------------------------
    minisoc_spi_tx u_tx (
        .spi_sclk  (spi_sclk),
        .spi_cs_n  (spi_cs_n),
        .rst_n     (rst_n),
        .read_data (read_data),
        .spi_miso  (spi_miso)
    );

    // -------------------------------------------------------------------------
    // version_dbg (duplica VERSION 0x0D do core)
    // -------------------------------------------------------------------------
    localparam logic [31:0] VERSION_CONST = 32'h0000_0001;
    assign version_dbg = VERSION_CONST;

endmodule