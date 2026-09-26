# ============================================================
# Environment Constraints (Load e Driving Cell para SAED32)
# ============================================================

set LIB_NAME "saed32rvt_tt1p05v25c"
set TYP_CELL "NBUFFX4_RVT"
set TYP_PIN  "A"

# ============================================================
# Clocks do Sistema
# ============================================================

# 1. Clock do Sistema (AES e Registradores) - ex: 50 MHz
create_clock -name clk -period 20 [get_ports clk]
set_clock_uncertainty 0.5 [get_clocks clk]
set_clock_transition 0.1 [get_clocks clk]

# 2. Clock da Interface SPI - ex: 10 MHz (geralmente mais lento que o sistema)
# Ajuste o nome da porta 'sclk' conforme o seu RTL
create_clock -name sclk -period 100 [get_ports sclk]
set_clock_uncertainty 0.5 [get_clocks sclk]
set_clock_transition 0.1 [get_clocks sclk]

# 3. Relação entre os domínios de clock
# Informa ao DC que as temporizações cruzadas (CDC) não devem ser otimizadas como síncronas
set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks sclk]

# ============================================================
# Input delay
# ============================================================
# Entradas do domínio do sistema (reset, etc.)
set inputs_sys [remove_from_collection [all_inputs] [get_ports {clk sclk mosi cs_n}]]
if {[sizeof_collection $inputs_sys] > 0} {
    set_input_delay 3.0 -clock clk $inputs_sys
}

# Entradas do domínio SPI (mosi, cs_n, etc.)
set inputs_spi [get_ports {mosi cs_n}]
set_input_delay 5.0 -clock sclk $inputs_spi

# ============================================================
# Output delay
# ============================================================
# Saídas do domínio SPI (miso)
set outputs_spi [get_ports {miso}]
set_output_delay 5.0 -clock sclk $outputs_spi

# Outras saídas do sistema (se houver, como flags de debug)
set outputs_sys [remove_from_collection [all_outputs] $outputs_spi]
if {[sizeof_collection $outputs_sys] > 0} {
    set_output_delay 3.0 -clock clk $outputs_sys
}

# ============================================================
# Fanout e Environment
# ============================================================
set_max_fanout 8 [current_design]

set inputs_no_clks [remove_from_collection [all_inputs] [get_ports {clk sclk}]]
set_driving_cell -lib_cell $TYP_CELL -pin Y $inputs_no_clks

set cap_of_buffer [load_of $LIB_NAME/$TYP_CELL/$TYP_PIN]
set my_typical_load [expr 8.0 * $cap_of_buffer]

set_load $my_typical_load [all_outputs]
puts "INFO: Load de saida configurado para $my_typical_load (FO8)"