// =============================================================================
// minisoc_spi_tx.sv
//
// Transmissor MISO serial (Issue 4) no domínio spi_sclk.
//
// Função:
//   Serializar read_data[31:0] no MISO durante a 2ª transação (NOP, addr=0x3F),
//   conforme §5.1/§5.2 do Block Guide.
//
// Frame de 40 bits na resposta MISO:
//   [39:32] don't care (8 zeros)   -> master ignora
//   [31:0]  read_data[31:0]        -> valor latcheado na transação 1
//
// Timing (Mode 0):
//   - negedge spi_cs_n : carrega miso_shift_reg = {8'h00, read_data}
//   - posedge spi_sclk : master amostra MISO (DUT só lê MOSI/RX, não faz nada)
//   - negedge spi_sclk : DUT desloca miso_shift_reg <<= 1 (MISO atualiza)
//   - posedge spi_cs_n : flag cs_was_falling zerado (prepara próximo load)
//
// CDC read_data (clk) -> spi_sclk:
//   read_data_q é quasi-estático por construção (§4.1 / §5.4): só muda após
//   frame_pulse de uma requisição de leitura, que termina MUITO antes do CS
//   falling do NOP seguinte (T_CS_IDLE ≥ 50 ns >> 2-3 ciclos de clk).
//   NÃO se adiciona 2FF nem handshake: garantia dada pelo protocolo.
//
// Escopo:
//   - Load em negedge spi_cs_n (não em flag miso_loaded explícito — ver nota
//     acima: o toggle frame_valid_toggle já ocorreu antes do NOP começar).
//   - MISO = 0 quando spi_cs_n = 1 (single-slave, sem high-Z).
// =============================================================================

module minisoc_spi_tx (
    input  logic        spi_sclk,
    input  logic        spi_cs_n,
    input  logic        rst_n,
    input  logic [31:0] read_data,    // do core (clk domain, quasi-estático)
    output logic        spi_miso
);

    // -------------------------------------------------------------------------
    // Shift register de 40 bits: {8'h00, read_data}
    // -------------------------------------------------------------------------
    logic [39:0] miso_shift_reg;
    logic        cs_was_falling;   // 1 = load já foi feito neste frame

    always_ff @(negedge spi_sclk or negedge spi_cs_n or posedge spi_cs_n or
                negedge rst_n) begin
        if (!rst_n) begin
            miso_shift_reg <= 40'h0;
            cs_was_falling <= 1'b0;
        end else if (spi_cs_n) begin
            // posedge spi_cs_n (fim de frame): libera próximo load
            cs_was_falling <= 1'b0;
        end else if (!cs_was_falling) begin
            // Primeiro negedge com CS baixo = CS falling edge -> load
            miso_shift_reg <= {8'h00, read_data};
            cs_was_falling <= 1'b1;
        end else begin
            // negedge spi_sclk com CS baixo -> shift MSB-first
            miso_shift_reg <= {miso_shift_reg[38:0], 1'b0};
        end
    end

    // MISO = 0 quando CS alto, senão MSB do shift register
    assign spi_miso = spi_cs_n ? 1'b0 : miso_shift_reg[39];

endmodule