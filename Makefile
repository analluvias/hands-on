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
# SPI RX (Semana 5, Issue 2)
# ==========================================
SPI_DIR      = rtl/minisoc_spi
SPI_RX_FILES = $(SPI_DIR)/minisoc_spi_rx.sv
SPI_RX_TB    = $(TB_DIR)/minisoc_spi_rx_tb.sv
SPI_RX_TOP   = minisoc_spi_rx_tb

# ==========================================
# SPI core (Semana 5, Issue 3)
# ==========================================
SPI_CORE_FILES = $(SPI_DIR)/minisoc_spi_core.sv
SPI_CORE_TB    = $(TB_DIR)/minisoc_spi_core_tb.sv
SPI_CORE_TOP   = minisoc_spi_core_tb


# ==========================================
# SPI TX (Semana 5, Issue 4)
# ==========================================
SPI_TX_FILES = $(SPI_DIR)/minisoc_spi_tx.sv
SPI_TX_TB    = $(TB_DIR)/minisoc_spi_tx_tb.sv
SPI_TX_TOP   = minisoc_spi_tx_tb


# ==========================================
# SPI — integração top (Semana 5, Issue 5)
# ==========================================
SPI_TOP_FILES = $(SPI_DIR)/minisoc_spi_rx.sv \
                $(SPI_DIR)/minisoc_spi_core.sv \
                $(SPI_DIR)/minisoc_spi_tx.sv \
                $(SPI_DIR)/minisoc_spi.sv
SPI_TOP_TB    = $(TB_DIR)/minisoc_spi_tb.sv
SPI_TOP_TOP   = minisoc_spi_tb

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


#============================================
#             SPI RX
#============================================
spi_rx_lint:
	@echo "=== Lint SPI RX ==="
	vlogan $(VLOGAN_FLAGS) $(SPI_RX_FILES)

spi_rx_compile:
	vlogan -full64 -sverilog -kdb -timescale=$(TIMESCALE) \
		$(SPI_RX_FILES) $(SPI_RX_TB)
	vcs $(VCS_FLAGS) -top $(SPI_RX_TOP) -o simv_spi_rx \
		$(SPI_RX_FILES) $(SPI_RX_TB)

spi_rx_run: spi_rx_compile
	./simv_spi_rx

#===========================================
#			spi core
#===========================================

spi_core_lint:
	@echo "=== Lint SPI core (RTL) ==="
	vlogan $(VLOGAN_FLAGS) $(SPI_CORE_FILES)

spi_core_compile:
	vlogan -full64 -sverilog -kdb -timescale=$(TIMESCALE) \
		$(SPI_CORE_FILES) $(SPI_CORE_TB)
	vcs $(VCS_FLAGS) -top $(SPI_CORE_TOP) -o simv_spi_core \
		$(SPI_CORE_FILES) $(SPI_CORE_TB)

spi_core_run: spi_core_compile
	./simv_spi_core

# ==========================================
# SPI TX (Semana 5, Issue 4)
# ==========================================

spi_tx_lint:
	@echo "=== Lint SPI TX ==="
	vlogan $(VLOGAN_FLAGS) $(SPI_TX_FILES)

spi_tx_compile:
	vlogan -full64 -sverilog -kdb -timescale=$(TIMESCALE) \
		$(SPI_TX_FILES) $(SPI_TX_TB)
	vcs $(VCS_FLAGS) -top $(SPI_TX_TOP) -o simv_spi_tx \
		$(SPI_TX_FILES) $(SPI_TX_TB)

spi_tx_run: spi_tx_compile
	./simv_spi_tx


#===========================================
#	SPI CORE FLAGS
#===========================================
spi_lint:
	@echo "=== Lint SPI (top) ==="
	vlogan $(VLOGAN_FLAGS) $(SPI_TOP_FILES)

spi_compile:
	vlogan -full64 -sverilog -kdb -timescale=$(TIMESCALE) \
		$(SPI_TOP_FILES) $(SPI_TOP_TB)
	vcs $(VCS_FLAGS) -top $(SPI_TOP_TOP) -o simv_spi \
		$(SPI_TOP_FILES) $(SPI_TOP_TB)

spi_run: spi_compile
	./simv_spi

# ==========================================
# Clean
# ==========================================
clean_sim:
	rm -rf csrc simv* *.daidir novas* AN.DB ucli.key verdi* DVEfiles .vlogan* *.fsdb *.log

clean: clean_sim

# .PHONY atualizado
.PHONY: lint syntax compile run \
        pll_lint pll_syntax pll_compile pll_run \
        spi_rx_lint spi_rx_compile spi_rx_run \
        spi_core_lint spi_core_compile spi_core_run \
        spi_tx_lint spi_tx_compile spi_tx_run \
        spi_lint spi_compile spi_run \
        wave pll_wave clean clean_sim
