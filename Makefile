# ==========================================
# Diretórios
# ==========================================
RTL_DIR     = rtl/minisoc_aes
PLL_DIR     = rtl/minisoc_pll
TB_DIR      = tb
SYNTH_DIR   = syn
SCRIPTS_DIR = scripts
REPORT_DIR  = docs/reports
FM_DIR      = formal
UPF_DIR     = upf

# ==========================================
# AES (Semana 3)
# ==========================================
RTL_FILES = \
    $(RTL_DIR)/minisoc_aes_sbox.sv \
    $(RTL_DIR)/minisoc_aes_sub_bytes.sv \
    $(RTL_DIR)/minisoc_aes_shift_rows.sv \
    $(RTL_DIR)/minisoc_aes_mix_columns.sv \
    $(RTL_DIR)/minisoc_aes_add_round_key.sv \
    $(RTL_DIR)/minisoc_aes_inv_sbox.sv \
    $(RTL_DIR)/minisoc_aes_inv_sub_bytes.sv \
    $(RTL_DIR)/minisoc_aes_inv_shift_rows.sv \
    $(RTL_DIR)/minisoc_aes_inv_mix_columns.sv \
    $(RTL_DIR)/minisoc_aes_key_exp.sv \
    $(RTL_DIR)/minisoc_aes_dp.sv

TB_FILES = $(TB_DIR)/minisoc_aes_key_exp_dp_tb.sv
TOP      = minisoc_aes_key_exp_dp_tb

# ==========================================
# PLL (Semana 5)
# ==========================================
PLL_FILES = $(PLL_DIR)/minisoc_pll_mock.sv
PLL_TB    = $(TB_DIR)/minisoc_pll_mock_tb.sv
PLL_TOP   = minisoc_pll_mock_tb

# ==========================================
# Flags
# ==========================================
TIMESCALE = 1ns/1ps

VLOGAN_FLAGS = -full64 \
               -sverilog \
               -kdb \
               -timescale=$(TIMESCALE) \
               +lint=all,noVCDE,noNS

VCS_FLAGS = -full64 \
            -sverilog \
            -timescale=$(TIMESCALE) \
            -debug_access+all \
            -kdb

# ==========================================
# AES — lint / syntax / compile / run
# ==========================================
lint:
	@echo "=== Lint AES ==="
	vlogan $(VLOGAN_FLAGS) $(RTL_FILES)

syntax:
	vlogan $(VLOGAN_FLAGS) $(RTL_FILES) $(TB_FILES)

compile: syntax
	vcs $(VCS_FLAGS) -top $(TOP) $(RTL_FILES) $(TB_FILES)

run: compile
	./simv

# ==========================================
# PLL — lint / syntax / compile / run
# ==========================================
pll_lint:
	@echo "=== Lint PLL ==="
	vlogan $(VLOGAN_FLAGS) $(PLL_FILES)

pll_syntax:
	vlogan $(VLOGAN_FLAGS) $(PLL_FILES) $(PLL_TB)

pll_compile: pll_syntax
	vcs $(VCS_FLAGS) -top $(PLL_TOP) -o simv_pll $(PLL_FILES) $(PLL_TB)

pll_run: pll_compile
	./simv_pll

# ==========================================
# Waveform
# ==========================================
wave:
	verdi -ssf aes_spi.fsdb &

pll_wave:
	verdi -ssf pll.fsdb &

# ==========================================
# Clean
# ==========================================
clean_sim:
	rm -rf csrc simv* *.daidir novas* AN.DB ucli.key verdi* DVEfiles .vlogan* *.fsdb *.log

clean: clean_sim

.PHONY: lint syntax compile run \
        pll_lint pll_syntax pll_compile pll_run \
        wave pll_wave clean clean_sim