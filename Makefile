# ==========================================
# Diretórios
# ==========================================
RTL_DIR     = rtl/minisoc_aes
TB_DIR      = tb
SYNTH_DIR   = syn
SCRIPTS_DIR = scripts
REPORT_DIR  = docs/reports
FM_DIR      = formal
UPF_DIR     = upf

# ==========================================
# Arquivos do RTL (Semana 2)
# ==========================================
RTL_FILES = \
    $(RTL_DIR)/minisoc_aes_sbox.sv \
    $(RTL_DIR)/minisoc_aes_sub_bytes.sv \
    $(RTL_DIR)/minisoc_aes_shift_rows.sv \
    $(RTL_DIR)/minisoc_aes_inv_sbox.sv \
    $(RTL_DIR)/minisoc_aes_inv_sub_bytes.sv \
    $(RTL_DIR)/minisoc_aes_inv_shift_rows.sv

TB_FILES = \
    $(TB_DIR)/tb_semana_02.sv

# ==========================================
# Top do testbench
# ==========================================
TOP = tb_semana_02

# ==========================================
# Flags
# ==========================================
TIMESCALE = 1ns/1ps

# Flags para o Vlogan (Linting rígido habilitado)
VLOGAN_FLAGS = -full64 \
               -sverilog \
               -kdb \
			   -timescale=$(TIMESCALE) \
               +lint=all,noVCDE

VCS_FLAGS = -full64 \
            -timescale=$(TIMESCALE) \
            -debug_access+all \
            -kdb

# ==========================================
# Target de Lint (Meta: Zero erros)
# ==========================================
lint:
	@echo "=========================================="
	@echo "  Executando Lint nos arquivos RTL...    "
	@echo "=========================================="
	vlogan $(VLOGAN_FLAGS) $(RTL_FILES)

# ==========================================
# Verificação de sintaxe (RTL + TB)
# ==========================================
syntax:
	vlogan $(VLOGAN_FLAGS) \
		$(RTL_FILES) \
		$(TB_FILES)

# ==========================================
# Compilação / Elaboração
# ==========================================
compile: syntax
	vcs $(VCS_FLAGS) -top $(TOP)

# ==========================================
# Simulação Autoverificável
# ==========================================
run: compile
	./simv

# ==========================================
# Abrir waveform (FSDB)
# ==========================================
wave:
	verdi -ssf aes_spi.fsdb &

# ==========================================
# Limpeza da simulação
# ==========================================
clean_sim:
	rm -rf \
		csrc \
		simv* \
		*.daidir \
		novas* \
		AN.DB \
		ucli.key \
		verdi* \
		DVEfiles \
		.vlogan* \
		*.fsdb \
		*.log

clean: clean_sim

.PHONY: lint syntax compile run wave clean clean_sim