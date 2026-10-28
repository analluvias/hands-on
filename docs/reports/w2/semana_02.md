# Relatório de Atividades - Semana 02

## 1. Resumo Executivo
Nesta semana foram desenvolvidos e validados os blocos combinacionais primários do datapath do AES (tanto diretos quanto inversos), conforme o padrão FIPS-197:
- **minisoc_aes_sbox.sv:** Tabela de substituição direta de 8 bits (Lookup Table de 256 entradas baseada na Figura 7 da FIPS-197).
- **minisoc_aes_sub_bytes.sv:** Substituição paralela de 16 bytes (128 bits) instanciando 16 S-Boxes diretas.
- **minisoc_aes_shift_rows.sv:** Reordenação direta de fios (deslocamento circular de linhas à esquerda) em 128 bits.
- **minisoc_aes_inv_sbox.sv (Bônus):** Tabela de substituição inversa de 8 bits (Lookup Table de 256 entradas baseada na Figura 14 da FIPS-197).
- **minisoc_aes_inv_sub_bytes.sv (Bônus):** Substituição inversa paralela de 16 bytes (128 bits) instanciando 16 S-Boxes inversas.
- **minisoc_aes_inv_shift_rows.sv (Bônus):** Reordenação inversa de fios (deslocamento circular de linhas à direita) em 128 bits.

---

## 2. Resultados das Simulações
A validação foi executada via testbench autoverificável (**tb/tb_semana_02.sv**) compilado e executado através do Synopsys VCS (**make run**).

### Cobertura de Testes:
1. **Varredura Completa da S-Box Direta e Inversa:**
   - 256/256 entradas testadas (0x00 a 0xFF) e validadas contra as tabelas de referência.
   - Pontos de checagem: **sbox(0x00) == 0x63** e **sbox(0x53) == 0xed**.
2. **Vetores FIPS-197 (Apêndice B):**
   - **Rodada 1:** Validação com sucesso nas etapas **Start of Round** -> **After SubBytes** -> **After ShiftRows**.
   - **Rodada 10:** Validação com sucesso nas etapas **Start of Round** -> **After SubBytes** -> **After ShiftRows**.
3. **Validação das Transformações Inversas (Bônus):**
   - Confirmação da propriedade de identidade para vetores aleatórios e conhecidos:
     - **InvSubBytes(SubBytes(x)) == x**
     - **InvShiftRows(ShiftRows(x)) == x**

**Status da Simulação:** PASS (0 Erros)

---

## 3. Relatório de Lint
A análise de linting foi executada via Synopsys Vlogan (**make lint**) com as flags **+lint=all,noVCDE**.
- **Arquivos analisados:** 
  - `rtl/minisoc_aes/minisoc_aes_sbox.sv`
  - `rtl/minisoc_aes/minisoc_aes_sub_bytes.sv`
  - `rtl/minisoc_aes/minisoc_aes_shift_rows.sv`
  - `rtl/minisoc_aes/minisoc_aes_inv_sbox.sv`
  - `rtl/minisoc_aes/minisoc_aes_inv_sub_bytes.sv`
  - `rtl/minisoc_aes/minisoc_aes_inv_shift_rows.sv`
- **Resultado:** 0 Erros e 0 Warnings impeditivos.

---

## 4. Dúvidas e Ambiguidades Identificadas no Block Guide (v1.0.0)
- **Troca de Ownership:** Comportamento esperado caso **MEM_SEL_AES** seja alterado enquanto **BUSY == 1**.
- **Endereço Base:** Se o processamento multi-bloco assume sempre o endereço inicial **0x000** na memória compartilhada ou se há suporte a registrador de offset.
- **Tratamento de Erros:** Cenários exatos e condições de disparo da flag **ERROR** no registrador de status (ex: combinações de modos inválidos ou `NUM_BLOCKS = 0`).

---

## 5. Próximos Passos (Semana 3)
- Elaboração do **Documento de Microarquitetura v1.0** em `docs/architecture/` (diagrama de blocos interno, microarquitetura iterativa do AES, FSM do `minisoc_aes_top`, estratégia de CDC com sincronização por toggle e sequência de reset do domínio do sistema).
- Implementação dos módulos **MixColumns** e **AddRoundKey**.
- Implementação da transformação inversa **InvMixColumns** (necessária à decriptação nos modos ECB, CBC e PCBC).
- Testes unitários com os valores intermediários da norma FIPS-197 (Apêndice B para cifragem e Apêndice C.1 para cifragem inversa).
- Apresentação da microarquitetura ao verificador parceiro.