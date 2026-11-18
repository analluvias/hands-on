// =============================================================================
// minisoc_spi_rx.sv
//
// Receptor SPI Mode 0 no domínio spi_sclk.
//
// Block Guide §5.1: SPI Mode 0 (CPOL=0, CPHA=0), MSB-first.
// MOSI é amostrado na BORDA DE SUBIDA de spi_sclk.
//
// Frame de 40 bits (Block Guide §5.2):
//   bit 39    : RWb       (0=write, 1=read)
//   bit 38:33 : ADDR[5:0]
//   bit 32    : RSV       (deve ser 0; mascarado para 0 no output)
//   bit 31:0  : DATA[31:0]
//
// Handoff para o domínio clk (Issue 3):
//   - frame_data[39:0] é estável após o 40º bit.
//   - frame_valid_toggle (1 bit, alterna) marca a chegada de um novo frame.
//     O 2FF sync + edge detector do lado clk detecta a alternância e captura
//     frame_data.
//
// Reset:
//   - rst_n (async global).
//   - posedge spi_cs_n (fim de frame, abort): reset assíncrono de bit_cnt e
//     shift_reg. O SPI master NÃO envia clock enquanto CS está alto, então um
//     reset síncrono ao spi_sclk nunca dispararia entre frames. Sem o reset
//     por CS, um frame abortado no meio deixaria bit_cnt != 0 e o próximo
//     frame seria mal capturado.
//     frame_data e frame_valid_toggle NÃO são resetados aqui - permanecem
//     estáveis para o handoff ao domínio clk.
//
// Escopo (Issue 2):
//   - Fase de recepção serial pura.
//   - SEM decode de endereço.
//   - SEM sincronização para clk (Issue 3).
// =============================================================================

module minisoc_spi_rx (
    input  logic        spi_sclk,           // gerado pelo SPI master
    input  logic        spi_cs_n,           // chip select, ativo baixo
    input  logic        spi_mosi,           // master out, slave in
    input  logic        rst_n,              // reset assíncrono do sistema
    output logic [39:0] frame_data,         // frame capturado (RSV mascarado p/ 0)
    output logic        frame_valid_toggle  // alterna 1x por frame completo
);

    logic [5:0]  bit_cnt;
    logic [39:0] shift_reg;

    // Próximo valor do shift register: desloca à esquerda, insere no LSB.
    // Após 40 shifts, shift_reg[39] = primeiro bit (RWb) etc.
    wire [39:0] next_frame = {shift_reg[38:0], spi_mosi};

    always_ff @(posedge spi_sclk or negedge rst_n or posedge spi_cs_n) begin
        if (!rst_n) begin
            // Reset global: inicializa tudo
            bit_cnt            <= 6'd0;
            shift_reg          <= 40'd0;
            frame_data         <= 40'd0;
            frame_valid_toggle <= 1'b0;
        end else if (spi_cs_n) begin
            // CS idle (fim de frame, abort, ou idle). Reset do estado por-frame.
            // NÃO reseta frame_data nem toggle.
            bit_cnt   <= 6'd0;
            shift_reg <= 40'd0;
        end else begin
            // CS ativo: amostra o bit atual e avança.
            shift_reg <= next_frame;

            if (bit_cnt == 6'd39) begin
                // 40º bit: frame completo.
                // Mascara RSV (bit 32) para 0 e publica o frame.
                frame_data <= {next_frame[39:33], 1'b0, next_frame[31:0]};
                frame_valid_toggle <= ~frame_valid_toggle;
                // Reset do contador: permite capturar múltiplos frames
                // consecutivos na mesma janela CS (raro, mas seguro).
                bit_cnt <= 6'd0;
            end else begin
                bit_cnt <= bit_cnt + 6'd1;
            end
        end
    end

endmodule