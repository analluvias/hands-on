# Arquitetura 

### 1. Estratégia de Clock, Reset e CDC (Clock Domain Crossing)
---

### 1.1 Domínios de clock do sistema
---
O sistema é estruturado em dois domínios de clock distintos e assíncronos entre si:

1. **Domínio do Clock Serial (SCLK)**
* **Natureza**: Clock intermitente, fornecido externamente pelo mestre SPI durante as transmissões.
* **Abrangência**: Restrito ao submódulo SPI_PHY (registrador de deslocamento, contador de bits e linha miso). 

2. **Domínio do Clock do Sistema (clk_sys)**
* **Natureza**: Clock contínuo de alta frequência gerado internamente pelo bloco de PLL.   
* **Abrangência**: Alimenta o banco de registradores (SPI_REGBANK), o núcleo criptográfico (AES CORE), a interface de memória (MEMORY DATA SYSTEM) e o circuito de sincronização do bloco de RESET.

---
### 1.2 Bloco pll mockado e sinal
---
* Geração de Clock: O bloco PLL_MOCKED recebe o relógio bruto de referência externa clk_osc (pino clk from OSC) e sintetiza o clock contínuo do sistema clk_sys.
* Inicialização e Trava de Estabilidade (locked):
    * Ao sair do reset, o PLL inicializa automaticamente em um estado de configuração padrão (default) e inicia o processo de travamento de frequência.   
    * Enquanto o sinal do clock estiver se ajustando, o sinal de status locked permanece desativado (0).   
    * Assim que o clk_sys atinge estabilidade de fase e frequência, o PLL sinaliza locked = 1.
* Uso do Sinal locked no Sistema:
    * **Proteção no Banco de Registradores (SPI_REGBANK)**: O sinal locked é enviado ao banco de registradores como uma condição de enable de hardware. A reconfiguração dos bits do PLL (registrador PLL_CONFIG no endereço 0x20) é fisicamente bloqueada enquanto locked == 0, sendo permitida apenas após a confirmação de estabilidade (locked == 1).   
    * **Habilitação de Segurança no AES (AES CORE)**: O sinal locked atua como condição de liberação da FSM do AES, garantindo que o processamento das rodadas não inicie com um clock instável.

---
### 1.3  Estratégia e Sincronização de Reset
---
O sistema gerencia o reset para os dois domínios de clock de maneira diferenciada:   
1. **Reset do Domínio do Sistema (clk_sys):**
* **Módulo RESET_SYNC**: Recebe o pino externo assíncrono global_rst_n (ativo em nível baixo) e o relógio clk_sys.   
* **Funcionamento**: Utiliza um sincronizador de reset de 2 estágios (2-FF Reset Synchronizer).
* **Asserção**: Assíncrona (imediata ao nível baixo de global_rst_n), garantindo parada instantânea do circuito.
* **Desasserção**: Síncrona com a borda de subida de clk_sys, eliminando riscos de metaestabilidade e violações de recovery/removal time no SPI_REGBANK, AES CORE e MEMORY DATA SYSTEM.

2. **Reset do Domínio SPI (SCLK):**
* Como o SCLK é um clock descontínuo (não oscila na ausência de tráfego SPI), não se utiliza um sincronizador dependente de SCLK, evitando que o módulo fique preso no estado de reset.  
* A asserção inicial do SPI_PHY é realizada assincronamente pelo global_rst_n.   
* A recuperação e o reset funcional de estado são garantidos pelo sinal de seleção cs_n (Chip Select): quando a transmissão é finalizada e cs_n retorna ao nível alto (1), a FSM e os contadores da SPI_PHY são reinicializados síncronamente ao estado IDLE.
---
### 1.4. Travessia entre Domínios de Clock (CDC — Clock Domain Crossing)
---
A comunicação entre o SPI_PHY (domínio SCLK) e o SPI_REGBANK (domínio clk_sys) ocorre por travessia segura de dados e sinais de controle:   
1. **Sentido PHY → REGBANK (Recepção de Comandos/Dados via SPI):**
* A SPI_PHY coleta os bits recebidos em mosi e monta a palavra paralela de 32 bits rx_data[31:0].   
* Ao completar os 32 bits, a SPI_PHY gera um pulso de controle rx_valid de 1 ciclo no domínio SCLK.
* O sinal rx_valid atravessa para o domínio clk_sys passando por um Sincronizador de 2 Flip-Flops (2-FF Synchronizer) localizado na entrada do SPI_REGBANK.
* O barramento de dados rx_data[31:0] é amostrado pelo SPI_REGBANK somente após a detecção síncrona da borda do rx_valid no domínio clk_sys, garantindo estabilidade no barramento paralelo durante a leitura.

2. **Sentido REGBANK → PHY (Leitura de Status/Registradores via SPI):**
* Os dados lidos no banco de registradores (tx_data[31:0]) permanecem estáticos e estáveis durante todo o período em que cs_n estiver ativo, permitindo que a SPI_PHY faça a amostragem paralela sem riscos de metaestabilidade.
___
### 1. Conexões do Microcontrolador (Interface Externa do Chip)

O microcontrolador conversa com o IP de topo através de quatro interfaces bem delimitadas:

* **`SPI IF` (Interface de Controle e Configuração com o Microcontrolador)**:


* `sclk` *(Entrada)*: Clock da comunicação serial gerado pelo microcontrolador.


* `cs_n` *(Entrada)*: Chip Select (ativo em nível baixo) vindo do microcontrolador para habilitar o chip.


* `mosi` *(Entrada)*: *Master Out Slave In* — envio de comandos, chaves e configurações do microcontrolador para o IP.


* `miso` *(Saída)*: *Master In Slave Out* — envio de dados de leitura e status do IP de volta para o microcontrolador.




* **`GLOBAL RESET`** *(Entrada)*: Pino físico de reset assíncrono externo.


* **`clk from OSC`** *(Entrada)*: Relógio bruto direto de um oscilador externo de cristal.


* **`MEMORY DATA IF` (Interface de Dados com o Barramento/Memória Externa)**:


* `ext_data_in[127:0]` *(Entrada)*: Barramento de 128 bits de entrada para receber o texto plano ou texto cifrado.


* `ext_data_out[127:0]` *(Saída)*: Barramento de 128 bits de saída com o resultado processado pelo AES.





---

### 2. Entradas e Saídas Detalhadas de Cada Submódulo Interno

#### A. Bloco `RESET` (`RESET_SYNC`)

* **Entradas:**
* `global_rst_n`: Conectado diretamente ao pino externo `GLOBAL RESET`.


* `clk_sys`: Clock do sistema vindo do `PLL` para sincronização.




* **Saídas:**
* `rst_sys_n`: Reset sincronizado com o clock do sistema. Vai para o `PLL`, `SPI_REGBANK`, `AES CORE` e `MEMORY DATA SYSTEM`.





#### B. Bloco `PLL` (`PLL_MOCKED`)

* **Entradas:**
* `clk_osc`: Conectado ao pino de entrada `clk from OSC`.


* `rst_sys_n`: Reset do sistema vindo do bloco de `RESET`.


* `pll_config[... ]`: Bits de ajuste de frequência vindos do `SPI_REGBANK`.




* **Saídas:**
* `clk_sys`: Clock principal gerado e distribuído para todo o chip.


* `locked`: Sinal de status (1 = clock estável). Vai para o `SPI_REGBANK` e para o `AES CORE`.





#### C. Módulo `SPI` (Dividido em Dois Submódulos)

1. **`SPI_PHY` (Opera exclusivamente em `SCLK`)**:


* *Entradas:* `sclk`, `cs_n`, `mosi` (vindos do pino `SPI IF`) e `tx_data[31:0]` (vindo do `SPI_REGBANK`).


* *Saídas:* `miso` (vai para o pino `SPI IF`), `rx_data[31:0]` (palavra paralela montada de 32 bits) e `rx_valid` (pulso avisando que a palavra chegou).




2. **`SPI_REGBANK` (Opera em `clk_sys`)**:


* *Entradas:* `clk_sys`, `rst_sys_n`, `rx_data[31:0]`, `rx_valid` (passa por sincronizador de 2-FF CDC), `locked` (sinal do PLL) e `aes_valid_out` (sinal de feito do AES).


* *Saídas:* `tx_data[31:0]` (enviado para o `SPI_PHY`), `pll_config[... ]` (bits de configuração enviados ao PLL), `cipher_key[127:0]` (chave de 128 bits para o AES), `aes_start` (pulso de início para o AES) e `aes_enc_dec_sel` (seletor de cifrar/decifrar).





#### D. Bloco `AES CORE` (Opera em `clk_sys`)

* **Entradas:**
* `clk_sys`: Clock do sistema.


* `rst_sys_n`: Reset do sistema.


* `locked`: Sinal do PLL autorizando o início das operações.


* `cipher_key[127:0]`: Chave vinda do `SPI_REGBANK`.


* `start`: Pulso de início vindo do `SPI_REGBANK`.


* `encrypt_decrypt_sel`: Modo (1 = cifrar, 0 = decifrar) vindo do `SPI_REGBANK`.


* `data_in[127:0]`: Bloco de 128 bits a ser processado vindo do `MEMORY DATA SYSTEM`.




* **Saídas:**
* `data_out[127:0]`: Bloco de 128 bits processado enviado ao `MEMORY DATA SYSTEM`.


* `valid_out`: Pulso indicando o fim das 10 rodadas. Vai para o `SPI_REGBANK` (para atualizar o registrador de status) e para o `MEMORY DATA SYSTEM` (para gravar o dado).





#### E. Bloco `MEMORY / DATA SYSTEM`

* **Entradas:**
* `ext_data_in[127:0]`: Conectado à interface de topo `MEMORY DATA IF`.


* `aes_data_out[127:0]`: Resultado de 128 bits vindo do `AES CORE`.


* `aes_valid_out`: Sinal de confirmação de pronto vindo do `AES CORE`.




* **Saídas:**
* `ext_data_out[127:0]`: Conectado à interface de topo `MEMORY DATA IF`.


* `aes_data_in[127:0]`: Bloco de 128 bits fornecido para o `AES CORE`.

## Definição do mapa de registradores

Já que o mestre SPI vai precisar de enviar a chave, o comando de start e as configurações do PLL, é preciso definir "onde" (em quais endereços) ele vai escrever esses dados.

| Endereço (Hex) | Nome do Registrador | Tipo | Descrição e mapeamento |
| --- | --- | --- | --- |
| 0x00 | AES_CTRL | R/W | Controle do AES: <br> Bit [0]: <br> start (Escrever 1 inicia o processo. O hardware deve zerar automaticamente após 1 ciclo). <br><br> Bit [1]: <br> encrypt_decrypt_sel (1 = Cifrar, 0 = Decifrar).   
| 0x04 | AES_STATUS | R | Status do Sistema: <br> Bit [0]:  <br> valid_out / done (1 = AES terminou o bloco, dado pronto na memória).    <br>  <br> Bit [1]:  <br> pll_locked (1 = Relógio do sistema estabilizado).
| 0x10 | AES_KEY_0 |R/W | Bits [31:0] da cipher_key de 128 bits.
| 0x14 | AES_KEY_1 | R/W | Bits da cipher_key de 128 bits.
| 0x18 | AES_KEY_2 | R/W | Bits da cipher_key de 128 bits.
| 0x1C | AES_KEY_3 | R/W | Bits da cipher_key de 128 bits.
| 0x20 | PLL_CONFIG | R/W* | Configuração do PLL: <br><br> Bits de configuração para o PLL mockado.  <br> *Regra de Hardware: A escrita neste registrador só tem efeito se o sinal locked do PLL for verdadeiro.   

**notas**
* R/W significa Read/Write (Leitura e Escrita via SPI).

* R significa Read-Only (Apenas leitura. O mestre SPI não pode forçar o valid_out a ser 1, apenas o hardware do AES altera isso).

* O registrador de chave foi dividido em 4 ( AES_KEY_0 a 3) para acomodar os 128 bits no barramento.

* Bloqueio do PLL: Garante a integridade da reconfiguração do clock somente após a estabilização inicial do sinal locked