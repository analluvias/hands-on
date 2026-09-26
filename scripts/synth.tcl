# ============================================================
# Script de Síntese - SAED32_EDK
# Suporte a SystemVerilog (.sv) - Projeto Acelerador AES + SPI
# ============================================================

# 1. CARREGAR CONFIGURAÇÃO
source ./scripts/.synopsys_dc.setup

# 2. LER OS ARQUIVOS RTL (SYSTEMVERILOG)
# É necessário listar todos os arquivos do projeto na ordem correta de dependência
analyze -format sverilog [list \
    ./rtl/spi_interface.sv \
    ./rtl/sync_cdc.sv \
    ./rtl/reg_bank.sv \
    ./rtl/aes_core.sv \
    ./rtl/power_ctrl.sv \
    ./rtl/aes_spi_top.sv \
]

# 3. ELABORAR O DESIGN
# O topo do projeto agora é o aes_spi_top
elaborate aes_spi_top

# 4. LINKAR O DESIGN
link

# 5. Gerar o arquivo de netlist não mapeado (opcional)
write_file -format sverilog -hier -out ./syn/aes_spi_top_nao_mapeado.sv

# 6. CARREGAR CONSTRAINTS (SDC)
# O SDC será desenvolvido na Semana 7 (rodada inicial de síntese)
read_sdc ./scripts/constraints.sdc

# 7. SÍNTESE
puts "\n============================================================"
puts "INICIANDO SÍNTESE (SystemVerilog)..."
puts "============================================================"
compile_ultra

# 8. RELATÓRIOS PÓS-SÍNTESE
# Direcionando os relatórios para a pasta syn/
puts "\n============================================================"
puts "RELATÓRIOS PÓS-SÍNTESE"
puts "============================================================"

report_area -hierarchy > ./syn/area_pos.rpt
puts "\n[Área] Relatório salvo em: ./syn/area_pos.rpt"

report_timing > ./syn/timing_relatorio.rpt
puts "[Timing] Relatório salvo em: ./syn/timing_relatorio.rpt"

report_power > ./syn/power.rpt
puts "[Power] Relatório salvo em: ./syn/power.rpt"

report_constraint -all_violators -check_type setup > ./syn/setup_violations.rpt
puts "[Setup Violations] Relatório salvo em: ./syn/setup_violations.rpt"

report_constraint -all_violators -check_type hold > ./syn/hold_violations.rpt
puts "[Hold Violations] Relatório salvo em: ./syn/hold_violations.rpt"

# 9. EXPORTAR NETLIST
write -format sverilog -hierarchy -output ./syn/aes_spi_top_syn.sv
puts "\n[Netlist] SystemVerilog salvo em: ./syn/aes_spi_top_syn.sv"

write -format ddc -hierarchy -output ./syn/aes_spi_top_syn.ddc
puts "[Netlist] DDC salvo em: ./syn/aes_spi_top_syn.ddc"

# 10. SALVAR DESIGN EM MEMORY
save_designs -force ./syn/aes_spi_top.db
puts "[Design] Salvo em: ./syn/aes_spi_top.db"

# 11. FINALIZAR
puts "\n============================================================"
puts "SÍNTESE CONCLUÍDA COM SUCESSO (SystemVerilog)!"
puts "============================================================"