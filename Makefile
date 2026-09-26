# ==========================================
# Diretórios
# ==========================================
RTL_DIR     = rtl
TB_DIR      = tb
SYNTH_DIR   = syn
SCRIPTS_DIR = scripts
REPORT_DIR  = docs/reports
FM_DIR      = formal
UPF_DIR     = upf

# ==========================================
# Arquivos
# ==========================================
# PKG_FILES = $(RTL_DIR)/aes_spi_pkg.sv # Descomentar se for usar um package para structs/defines

RTL_FILES = \
    $(RTL_DIR)/spi_interface.sv \
    $(RTL_DIR)/sync_cdc.sv \
    $(RTL_DIR)/reg_bank.sv \
    $(RTL_DIR)/aes_core.sv \
    $(RTL_DIR)/power_ctrl.sv \
    $(RTL_DIR)/aes_spi_top.sv

TB_FILES = \
    $(TB_DIR)/tb_aes_spi_top.sv

# ==========================================
# Top do testbench
# ==========================================
TOP = tb_aes_spi_top

# ==========================================
# Flags
# ==========================================
TIMESCALE = 1ns/1ps

VLOGAN_FLAGS = -full64 \
               -sverilog \
               -kdb \
               +lint=all

VCS_FLAGS = -full64 \
            -timescale=$(TIMESCALE) \
            -debug_access+all \
            -kdb

# ==========================================
# Verificação de sintaxe
# ==========================================
syntax:
	vlogan $(VLOGAN_FLAGS) \
		$(RTL_FILES) \
		$(TB_FILES)
# Adicionar $(PKG_FILES) \ antes de $(RTL_FILES) se for utilizar packages.

# ==========================================
# Compilação / Elaboração
# ==========================================
compile: syntax
	vcs $(VCS_FLAGS) -top $(TOP)

# ==========================================
# Simulação
# ==========================================
run: compile
	./simv

# ==========================================
# Abrir waveform
# ==========================================
wave:
	verdi -ssf aes_spi.fsdb &

# ==========================================
# Síntese
# ==========================================
synth:
	dc_shell -x "source $(SCRIPTS_DIR)/.synopsys_dc.setup" -f $(SCRIPTS_DIR)/synth.tcl

# ==========================================
# Verificação formal
# ==========================================
fm:
	mkdir -p $(FM_DIR)/reports
	fm_shell -f $(FM_DIR)/formality_auto_using.tcl

# ==========================================
# Limpeza da síntese
# ==========================================
clean_synth:
	rm -rf \
		./aes_spi_top.ddc \
		./alib-52 \
		./default.svf \
		./work* \
		$(SYNTH_DIR)/*.rpt \
		$(SYNTH_DIR)/*.ddc \
		$(SYNTH_DIR)/*.db \
		$(SYNTH_DIR)/*_syn.v

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

# ==========================================
# Limpeza do Formality
# ==========================================
clean_fm:
	rm -rf \
		./FM_WORK \
		./FM_INFO \
		./formality.log \
		./fm_core* \
		./formality_svf/ \
		$(FM_DIR)/reports

# ==========================================
# Limpeza total
# ==========================================
clean: clean_sim clean_synth clean_fm

.PHONY: syntax compile run wave synth fm clean clean_sim clean_synth clean_fm