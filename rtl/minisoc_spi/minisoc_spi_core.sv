// =============================================================================
// minisoc_spi_core.sv
//
// Back-end do SPI no domínio clk (always-on).
//
// FIX IMPORTANTE (Issues 3):
//   Não existe registrador `frame_capture` intermediário. O decode usa
//   frame_data[39:0] DIRETAMENTE. frame_data é quasi-estático (§4.1): o RX
//   o atualiza junto com frame_valid_toggle no mesmo posedge spi_sclk, e o
//   2FF sync garante 2-3 ciclos de estabilidade antes de frame_pulse.
//   Registrar frame_data e ler o registrador no MESMO edge causaria leitura
//   do valor anterior (bug de 1 frame de atraso).
//
// Interface com o RX (Issue 2):
//   - frame_data[39:0]: quasi-estático enquanto toggle está estável.
//   - frame_valid_toggle: alterna 1x por frame completo.
//
// Layout dos registradores de controle (Block Guide §6.1/§6.3):
//   AES_CONTROL (0x0B): [0]=START (W1P), [1]=DECRYPT, [4:2]=MODE
//   SYSTEM_CONTROL (0x0E): [0]=MEM_SEL_AES, [1]=PLL_ENABLE, [3:2]=PLL_DIV_SEL
//   AES_STATUS (0x0C, RO): [0]=BUSY, [1]=DONE, [2]=ERROR, [11:3]=BLOCKS_DONE
//   SYSTEM_STATUS (0x0F, RO): [0]=PLL_LOCKED
//   VERSION (0x0D, RO): 32'h0000_0001
//   NOP (0x3F): leitura mantém read_data_q; escrita ignorada.
// =============================================================================

module minisoc_spi_core (
    input  logic         clk,
    input  logic         rst_n,

    // RX (domínio spi_sclk)
    input  logic [39:0]  frame_data,
    input  logic         frame_valid_toggle,

    // Status externos
    input  logic         status_busy,
    input  logic         status_done,
    input  logic         status_error,
    input  logic [8:0]   status_blocks_done,
    input  logic         pll_locked,

    // Config para o AES engine
    output logic [127:0] cfg_key,
    output logic [127:0] cfg_iv,
    output logic [63:0]  cfg_counter,
    output logic [8:0]   cfg_num_blocks,
    output logic [2:0]   cfg_mode,
    output logic         cfg_decrypt,
    output logic         cmd_start,

    // Para o MISO TX (Issue 4)
    output logic [31:0]  read_data,

    // --- Saídas para o PLL e o Memory Mux --------------------------------
    output logic         pll_enable,
    output logic [1:0]   pll_div_sel,
    output logic         mem_sel_aes
);

    // =========================================================================
    // 1. CDC: 2FF + edge detect
    // =========================================================================
    (* async_reg = "true" *) logic ff1, ff2;
    logic ff3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ff1 <= 1'b0;
            ff2 <= 1'b0;
            ff3 <= 1'b0;
        end else begin
            ff1 <= frame_valid_toggle;
            ff2 <= ff1;
            ff3 <= ff2;
        end
    end

    wire frame_pulse = ff2 ^ ff3;

    // =========================================================================
    // 2. Decode: frame_data DIRETO (quasi-estático)
    // =========================================================================
    wire        rwb   = frame_data[39];
    wire [5:0]  addr  = frame_data[38:33];
    wire [31:0] wdata = frame_data[31:0];

    // =========================================================================
    // 3. Register bank
    // =========================================================================
    logic [127:0] key_q;
    logic [127:0] iv_q;
    logic [63:0]  counter_q;
    logic [8:0]   num_blocks_q;
    logic         decrypt_q;
    logic [2:0]   mode_q;
    logic         mem_sel_aes_q;
    logic         pll_enable_q;
    logic [1:0]   pll_div_sel_q;

    localparam logic [5:0] ADDR_KEY0       = 6'h00;
    localparam logic [5:0] ADDR_KEY1       = 6'h01;
    localparam logic [5:0] ADDR_KEY2       = 6'h02;
    localparam logic [5:0] ADDR_KEY3       = 6'h03;
    localparam logic [5:0] ADDR_IV0        = 6'h04;
    localparam logic [5:0] ADDR_IV1        = 6'h05;
    localparam logic [5:0] ADDR_IV2        = 6'h06;
    localparam logic [5:0] ADDR_IV3        = 6'h07;
    localparam logic [5:0] ADDR_CTR_HI     = 6'h08;
    localparam logic [5:0] ADDR_CTR_LO     = 6'h09;
    localparam logic [5:0] ADDR_NUM_BLOCKS = 6'h0A;
    localparam logic [5:0] ADDR_AES_CTRL   = 6'h0B;
    localparam logic [5:0] ADDR_AES_STAT   = 6'h0C;
    localparam logic [5:0] ADDR_VERSION    = 6'h0D;
    localparam logic [5:0] ADDR_SYS_CTRL   = 6'h0E;
    localparam logic [5:0] ADDR_SYS_STAT   = 6'h0F;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_q         <= 128'd0;
            iv_q          <= 128'd0;
            counter_q     <= 64'd0;
            num_blocks_q  <= 9'd0;
            decrypt_q     <= 1'b0;
            mode_q        <= 3'd0;
            mem_sel_aes_q <= 1'b0;
            pll_enable_q  <= 1'b0;
            pll_div_sel_q <= 2'd0;
        end else if (frame_pulse && !rwb) begin
            case (addr)
                ADDR_KEY0:       key_q[127:96]    <= wdata;
                ADDR_KEY1:       key_q[95:64]     <= wdata;
                ADDR_KEY2:       key_q[63:32]     <= wdata;
                ADDR_KEY3:       key_q[31:0]      <= wdata;
                ADDR_IV0:        iv_q[127:96]     <= wdata;
                ADDR_IV1:        iv_q[95:64]      <= wdata;
                ADDR_IV2:        iv_q[63:32]      <= wdata;
                ADDR_IV3:        iv_q[31:0]       <= wdata;
                ADDR_CTR_HI:     counter_q[63:32] <= wdata;
                ADDR_CTR_LO:     counter_q[31:0]  <= wdata;
                ADDR_NUM_BLOCKS: num_blocks_q     <= wdata[8:0];
                ADDR_AES_CTRL: begin
                    decrypt_q <= wdata[1];
                    mode_q    <= wdata[4:2];
                    // wdata[0] (START) NÃO armazena - gera cmd_start
                end
                ADDR_SYS_CTRL: begin
                    mem_sel_aes_q <= wdata[0];
                    pll_enable_q  <= wdata[1];
                    pll_div_sel_q <= wdata[3:2];
                end
                default: ;
            endcase
        end
    end

    // =========================================================================
    // 4. cmd_start: pulso 1 ciclo quando START=1 é escrito em AES_CONTROL
    // =========================================================================
    logic cmd_start_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_start_q <= 1'b0;
        end else begin
            cmd_start_q <= 1'b0;
            if (frame_pulse && !rwb && (addr == ADDR_AES_CTRL) && wdata[0])
                cmd_start_q <= 1'b1;
        end
    end

    assign cmd_start = cmd_start_q;

    // =========================================================================
    // 5. Leitura
    // =========================================================================
    logic [31:0] read_data_q;

    wire [31:0] aes_status_word = {
        20'd0,
        status_blocks_done,   // [11:3]
        status_error,         // [2]
        status_done,          // [1]
        status_busy           // [0]
    };

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_data_q <= 32'd0;
        end else if (frame_pulse && rwb) begin
            case (addr)
                ADDR_KEY0:       read_data_q <= key_q[127:96];
                ADDR_KEY1:       read_data_q <= key_q[95:64];
                ADDR_KEY2:       read_data_q <= key_q[63:32];
                ADDR_KEY3:       read_data_q <= key_q[31:0];
                ADDR_IV0:        read_data_q <= iv_q[127:96];
                ADDR_IV1:        read_data_q <= iv_q[95:64];
                ADDR_IV2:        read_data_q <= iv_q[63:32];
                ADDR_IV3:        read_data_q <= iv_q[31:0];
                ADDR_CTR_HI:     read_data_q <= counter_q[63:32];
                ADDR_CTR_LO:     read_data_q <= counter_q[31:0];
                ADDR_NUM_BLOCKS: read_data_q <= {23'd0, num_blocks_q};
                ADDR_AES_CTRL:   read_data_q <= {27'd0, mode_q, decrypt_q, 1'b0};
                ADDR_AES_STAT:   read_data_q <= aes_status_word;
                ADDR_VERSION:    read_data_q <= 32'h0000_0001;
                ADDR_SYS_CTRL:   read_data_q <= {28'd0, pll_div_sel_q, pll_enable_q, mem_sel_aes_q};
                ADDR_SYS_STAT:   read_data_q <= {31'd0, pll_locked};
                default: ;
            endcase
        end
    end

    assign read_data = read_data_q;

    // =========================================================================
    // 6. Saídas
    // =========================================================================
    assign cfg_key        = key_q;
    assign cfg_iv         = iv_q;
    assign cfg_counter    = counter_q;
    assign cfg_num_blocks = num_blocks_q;
    assign cfg_mode       = mode_q;
    assign cfg_decrypt    = decrypt_q;

    // Saídas de controle para PLL e memory mux (§5.4 §6.3)
    assign pll_enable  = pll_enable_q;
    assign pll_div_sel = pll_div_sel_q;
    assign mem_sel_aes = mem_sel_aes_q;
endmodule