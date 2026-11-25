// =============================================================================
// minisoc_aes_top_tb.sv
//
// Testbench de bloco do AES + memória compartilhada (Semana 6, Issue 4).
//
// Cobertura:
//   - 18 casos válidos: ECB/CBC/CTR × encrypt/decrypt × 1/2/256 blocos.
//     Carrega {MODE}_{DIR}_{N}_input.mem via interface externa,
//     executa, compara toda a memória com {MODE}_{DIR}_{N}_expected.mem.
//   - 7 casos inválidos (NUM_BLOCKS=0, 257; MODE=110, 111, 010, 011, 100).
//     Verifica ERROR=1, DONE=0, BLOCKS_DONE=0.
//   - DONE sticky: cada caso válido exige DONE=1 ao final; o próximo START
//     precisa zerá-lo (fase 1 do wait_done_or_error), senão fail.
//
// Dependências:
//   - tb/vectors/test_cases.svh (auto-gerado por tools/aes_ref_model.py)
//   - tb/vectors/*.mem         (idem)
//   Rode `make vectors` antes de `make aes_mem_run`.
//
// Layout de memória (§7.1):
//   mem[4i+0] = bits [127:96]
//   mem[4i+1] = bits [ 95:64]
//   mem[4i+2] = bits [ 63:32]
//   mem[4i+3] = bits [ 31: 0]
// =============================================================================

`timescale 1ns/1ps
`default_nettype none


module minisoc_aes_top_tb;

    // =========================================================================
    // Parâmetros
    // =========================================================================
    localparam int WAIT_TIMEOUT_CYCLES = 100_000;
    localparam int MEM_WORDS           = 1024;

    // Constantes fixas — devem casar com tools/aes_ref_model.py
    localparam logic [127:0] KEY_CONST     = 128'h000102030405060708090a0b0c0d0e0f;
    localparam logic [127:0] IV_CONST      = 128'h101112131415161718191a1b1c1d1e1f;
    localparam logic [63:0]  COUNTER_CONST = 64'hDEADBEEFCAFEBABE;

    `include "tb/vectors/test_cases.svh"


    // =========================================================================
    // Clocks — 100 MHz, 5 ns de offset (fases opostas)
    // =========================================================================
    logic clk     = 1'b0;
    logic mem_clk = 1'b1;
    always #5.0 clk     = ~clk;
    always #5.0 mem_clk = ~mem_clk;

    // =========================================================================
    // Sinais do DUT
    // =========================================================================
    logic          rst_n          = 1'b0;

    logic [127:0]  cfg_key        = '0;
    logic [127:0]  cfg_iv         = '0;
    logic [63:0]   cfg_counter    = '0;
    logic [8:0]    cfg_num_blocks = '0;
    logic [2:0]    cfg_mode       = '0;
    logic          cfg_decrypt    = 1'b0;
    logic          cmd_start      = 1'b0;

    logic          status_busy;
    logic          status_done;
    logic          status_error;
    logic [8:0]    status_blocks_done;

    logic [9:0]    aes_mem_addr;
    logic [31:0]   aes_mem_wdata;
    logic          aes_mem_wr_en;
    logic [31:0]   aes_mem_rdata;

    logic [31:0]   ext_mem_i_data  = '0;
    logic          ext_mem_i_wr_en = 1'b0;
    logic [9:0]    ext_mem_i_addr  = '0;
    logic [31:0]   ext_mem_o_data;

    logic          mem_sel_aes     = 1'b0;

    // =========================================================================
    // DUT
    // =========================================================================
    minisoc_aes_top u_aes (
        .clk                (clk),
        .rst_n              (rst_n),
        .cfg_key            (cfg_key),
        .cfg_iv             (cfg_iv),
        .cfg_counter        (cfg_counter),
        .cfg_num_blocks     (cfg_num_blocks),
        .cfg_mode           (cfg_mode),
        .cfg_decrypt        (cfg_decrypt),
        .cmd_start          (cmd_start),
        .status_busy        (status_busy),
        .status_done        (status_done),
        .status_error       (status_error),
        .status_blocks_done (status_blocks_done),
        .mem_addr           (aes_mem_addr),
        .mem_wdata          (aes_mem_wdata),
        .mem_wr_en          (aes_mem_wr_en),
        .mem_rdata          (aes_mem_rdata)
    );

    minisoc_memory u_mem (
        .mem_clk     (mem_clk),
        .mem_i_data  (ext_mem_i_data),
        .mem_i_wr_en (ext_mem_i_wr_en),
        .mem_i_addr  (ext_mem_i_addr),
        .mem_o_data  (ext_mem_o_data),
        .aes_clk     (clk),
        .aes_addr    (aes_mem_addr),
        .aes_wdata   (aes_mem_wdata),
        .aes_wr_en   (aes_mem_wr_en),
        .aes_rdata   (aes_mem_rdata),
        .mem_sel_aes (mem_sel_aes)
    );

    // =========================================================================
    // Storage local para arquivos .mem
    // =========================================================================
    logic [31:0] input_mem    [0:MEM_WORDS-1];
    logic [31:0] expected_mem [0:MEM_WORDS-1];

    // =========================================================================
    // Estatísticas
    // =========================================================================
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    int case_errors;
    logic timed_out;

        // =========================================================================
    // Helpers de metadata — desempacotam VALID_CASES[i] e INVALID_CASES[i]
    // =========================================================================
    function automatic logic [2:0] case_mode(input logic [15:0] packed_case);
        return packed_case[2:0];
    endfunction

    function automatic logic case_decrypt(input logic [15:0] packed_case);
        return packed_case[3];
    endfunction

    function automatic logic [8:0] case_nblocks(input logic [15:0] packed_case);
        return packed_case[12:4];
    endfunction

    function automatic string mode_str(input logic [2:0] m);
        case (m)
            3'b000: return "ECB";
            3'b001: return "CBC";
            3'b101: return "CTR";
            default: return "INVALID";
        endcase
    endfunction

    function automatic string dir_str(input logic d);
        return d ? "dec" : "enc";
    endfunction

    function automatic string valid_input_path(input int i);
        return $sformatf("tb/vectors/%s_%s_%0d_input.mem",
                         mode_str(case_mode(VALID_CASES[i])),
                         dir_str(case_decrypt(VALID_CASES[i])),
                         case_nblocks(VALID_CASES[i]));
    endfunction

    function automatic string valid_expected_path(input int i);
        return $sformatf("tb/vectors/%s_%s_%0d_expected.mem",
                         mode_str(case_mode(VALID_CASES[i])),
                         dir_str(case_decrypt(VALID_CASES[i])),
                         case_nblocks(VALID_CASES[i]));
    endfunction

    // =========================================================================
    // Tasks auxiliares
    // =========================================================================
    task automatic ext_write(input logic [9:0] addr, input logic [31:0] data);
        @(negedge mem_clk);
        ext_mem_i_addr  = addr;
        ext_mem_i_data  = data;
        ext_mem_i_wr_en = 1'b1;
        @(negedge mem_clk);
        ext_mem_i_wr_en = 1'b0;
    endtask

    task automatic ext_read(input logic [9:0] addr, output logic [31:0] data);
        @(negedge mem_clk);
        ext_mem_i_addr  = addr;
        ext_mem_i_wr_en = 1'b0;
        @(posedge mem_clk);
        #1;
        data = ext_mem_o_data;
    endtask

    task automatic pulse_start();
        @(negedge clk);
        cmd_start = 1'b1;
        @(negedge clk);
        cmd_start = 1'b0;
    endtask

    // Aguarda DONE=0 (limpeza do START), depois DONE=1 ou ERROR=1.
    // timed_out=1 se estourar timeout em qualquer fase.
    task automatic wait_done_or_error(output logic timed_out);
        int cycles;
        timed_out = 1'b0;

        // Fase 1: aguarda DONE zerar (novo START)
        cycles = 0;
        while (status_done === 1'b1) begin
            @(posedge clk);
            cycles++;
            if (cycles >= 100) begin
                $error("DONE não foi limpo pelo START");
                timed_out = 1'b1;
                return;
            end
        end

        // Fase 2: aguarda DONE=1 (sucesso) ou ERROR=1 (falha)
        cycles = 0;
        while (!(status_done === 1'b1 || status_error === 1'b1)) begin
            @(posedge clk);
            cycles++;
            if (cycles >= WAIT_TIMEOUT_CYCLES) begin
                timed_out = 1'b1;
                return;
            end
        end
    endtask

    task automatic load_mem_files(input string in_file, input string exp_file);
        foreach (input_mem[i])    input_mem[i]    = 'x;
        foreach (expected_mem[i]) expected_mem[i] = 'x;
        $readmemh(in_file,  input_mem);
        $readmemh(exp_file, expected_mem);
        if ($isunknown(input_mem[0])) begin
            $fatal(1, "load_mem_files: falha ao carregar %s (rode `make vectors`)", in_file);
        end
        if ($isunknown(expected_mem[0])) begin
            $fatal(1, "load_mem_files: falha ao carregar %s (rode `make vectors`)", exp_file);
        end
    endtask

    // =========================================================================
    // Execução de um caso válido
    // =========================================================================
    task automatic run_valid_case(input int idx);
        string    case_name;
        logic [31:0] rd;
        int       mem_errors;

        case_name = $sformatf("%s_%s_%0d (mode=%03b dec=%0d nb=%0d)",
                        mode_str(case_mode(VALID_CASES[idx])),
                        dir_str(case_decrypt(VALID_CASES[idx])),
                        case_nblocks(VALID_CASES[idx]),
                        case_mode(VALID_CASES[idx]),
                        case_decrypt(VALID_CASES[idx]),
                        case_nblocks(VALID_CASES[idx]));
        test_count++;
        case_errors = 0;
        mem_errors  = 0;

        // 1) Carrega arquivos .mem
        load_mem_files(valid_input_path(idx), valid_expected_path(idx));

        // 2) Ownership externo
        @(negedge clk);
        mem_sel_aes = 1'b0;
        repeat (2) @(posedge clk);

        // 3) Carrega memória via interface externa
        for (int i = 0; i < MEM_WORDS; i++)
            ext_write(i[9:0], input_mem[i]);

        // 4) Configura cfg_*
        @(negedge clk);
        cfg_key        = KEY_CONST;
        cfg_iv         = IV_CONST;
        cfg_counter    = COUNTER_CONST;
        cfg_num_blocks = case_nblocks(VALID_CASES[idx]);
        cfg_mode       = case_mode(VALID_CASES[idx]);
        cfg_decrypt    = case_decrypt(VALID_CASES[idx]);
        repeat (2) @(posedge clk);

        // 5) Ownership AES (swap com AES ocioso — §7.2)
        @(negedge clk);
        mem_sel_aes = 1'b1;
        repeat (2) @(posedge clk);

        // 6) START
        pulse_start();

        // 7) Aguarda DONE/ERROR
        wait_done_or_error(timed_out);
        if (timed_out) begin
            $error("[%s] TIMEOUT aguardando DONE/ERROR", case_name);
            fail_count++;
            return;
        end

        // 8) Verifica status
        if (status_error !== 1'b0) begin
            $error("[%s] status_error=%b (esperado 0)", case_name, status_error);
            case_errors++;
        end
        if (status_done !== 1'b1) begin
            $error("[%s] status_done=%b (esperado 1)", case_name, status_done);
            case_errors++;
        end
        if (status_blocks_done !== case_nblocks(VALID_CASES[idx])) begin
            $error("[%s] status_blocks_done=%0d (esperado %0d)",
                   case_name, status_blocks_done, case_nblocks(VALID_CASES[idx]));
            case_errors++;
        end
        if (status_busy !== 1'b0) begin
            $error("[%s] status_busy=%b (esperado 0 após DONE)", case_name, status_busy);
            case_errors++;
        end

        // 9) Devolve ownership ao externo
        @(negedge clk);
        mem_sel_aes = 1'b0;
        repeat (2) @(posedge clk);

        // 10) Compara toda a memória com _expected.mem
        for (int i = 0; i < MEM_WORDS; i++) begin
            ext_read(i[9:0], rd);
            if (rd !== expected_mem[i]) begin
                if (mem_errors < 5) begin
                    $error("[%s] mem[%0d]: got %h expected %h",
                           case_name, i, rd, expected_mem[i]);
                end
                mem_errors++;
            end
        end
        if (mem_errors > 0) begin
            $display("[%s] MEMORY MISMATCH: %0d word(s) divergem", case_name, mem_errors);
            case_errors += mem_errors;
        end

        // 11) Resultado
        if (case_errors == 0) begin
            $display("[PASS] %s", case_name);
            pass_count++;
        end else begin
            $display("[FAIL] %s (%0d erro(s))", case_name, case_errors);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Execução de um caso inválido
    // =========================================================================
    task automatic run_invalid_case(input int idx);
        string case_name;

        case_name = $sformatf("INVALID[%0d] mode=%03b dec=%0d nb=%0d",
                              idx,
                              case_mode(INVALID_CASES[idx]),
                              case_decrypt(INVALID_CASES[idx]),
                              case_nblocks(INVALID_CASES[idx]));
        test_count++;
        case_errors = 0;

        // Ownership externo
        @(negedge clk);
        mem_sel_aes = 1'b0;
        repeat (2) @(posedge clk);

        // Config inválida
        @(negedge clk);
        cfg_key        = KEY_CONST;
        cfg_iv         = IV_CONST;
        cfg_counter    = COUNTER_CONST;
        cfg_num_blocks = case_nblocks(INVALID_CASES[idx]);
        cfg_mode       = case_mode(INVALID_CASES[idx]);
        cfg_decrypt    = case_decrypt(INVALID_CASES[idx]);
        repeat (2) @(posedge clk);

        // Ownership AES
        @(negedge clk);
        mem_sel_aes = 1'b1;
        repeat (2) @(posedge clk);

        // START
        pulse_start();

        // Aguarda ERROR
        wait_done_or_error(timed_out);
        if (timed_out) begin
            $error("[%s] TIMEOUT aguardando ERROR", case_name);
            fail_count++;
            return;
        end

        // Verifica status
        if (status_error !== 1'b1) begin
            $error("[%s] status_error=%b (esperado 1)", case_name, status_error);
            case_errors++;
        end
        if (status_done !== 1'b0) begin
            $error("[%s] status_done=%b (esperado 0 — sticky deve ser limpo)", case_name, status_done);
            case_errors++;
        end
        if (status_blocks_done !== 9'd0) begin
            $error("[%s] status_blocks_done=%0d (esperado 0)", case_name, status_blocks_done);
            case_errors++;
        end

        // Devolve ownership
        @(negedge clk);
        mem_sel_aes = 1'b0;
        repeat (2) @(posedge clk);

        if (case_errors == 0) begin
            $display("[PASS] %s", case_name);
            pass_count++;
        end else begin
            $display("[FAIL] %s (%0d erro(s))", case_name, case_errors);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Sequência principal
    // =========================================================================

    // Reset
    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);
    end

    // Runner
    initial begin
        // Garante que a Issue #3 rodou
        int fd;
        fd = $fopen("tb/vectors/test_cases.svh", "r");
        if (fd == 0) begin
            $fatal(1, "tb/vectors/test_cases.svh não encontrado — rode `make vectors`");
        end
        $fclose(fd);

        wait (rst_n === 1'b1);
        repeat (20) @(posedge clk);

        $display("=================================================");
        $display(" MiniSoC AES + Memory — bloco TB (Semana 6)");
        $display("=================================================");

        // --- Casos válidos ---
        $display("\n--- VÁLIDOS (ECB/CBC/CTR × enc/dec × 1/2/256) ---");
        for (int i = 0; i < NUM_VALID_CASES; i++)
            run_valid_case(i);

        // --- Casos inválidos ---
        $display("\n--- INVÁLIDOS (NB=0/257, MODE=110/111/010/011/100) ---");
        for (int i = 0; i < NUM_INVALID_CASES; i++)
            run_invalid_case(i);

        // --- Sumário ---
        $display("\n=================================================");
        $display(" RESULTADO: %0d/%0d PASS, %0d FAIL",
                 pass_count, test_count, fail_count);
        $display("=================================================");

        if (fail_count == 0) $display("=== ALL PASS ===");
        else                 $display("=== FAIL (%0d) ===", fail_count);

        $finish;
    end

    // Timeout global (sanity)
    initial begin
        #50_000_000; // 50 ms
        $error("TIMEOUT GLOBAL");
        $finish;
    end

endmodule

`default_nettype wire