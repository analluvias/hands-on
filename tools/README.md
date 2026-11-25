# AES Reference Model — Semana 6 (Issue #3)

Gera vetores de teste para a TB do AES+memória do MiniSoC AES.
Cobre **ECB (000), CBC (001) e CTR (101)** — sem PCBC/CFB/OFB.

## Dependências

**Nenhuma.** Python 3.6+. AES-128 é implementado no próprio script
(auto-testado contra o vetor FIPS-197 §C.1 antes de gerar qualquer
arquivo — se o self-test falhar, aborta).

## Uso

A partir da raiz do repositório:

```bash
python3 tools/aes_ref_model.py
```

Saída padrão: tb/vectors/. Para outro diretório:

```bash
python3 tools/aes_ref_model.py --out-dir /tmp/vectors
```


## Arquivos gerados

### Casos válidos (18)

`tb/vectors/{MODE}_{DIR}_{N}_input.mem` e `_expected.mem`.

- `MODE` ∈ `{ECB, CBC, CTR}`
- `DIR`  ∈ `{enc, dec}` — `enc` ⇒ `DECRYPT=0`, `dec` ⇒ `DECRYPT=1`
- `N`    ∈ `{1, 2, 256}` — `NUM_BLOCKS`

Cada `.mem` tem **1024 linhas**, uma palavra de 32 bits em hexadecimal
(8 chars lowercase), formato `$readmemh`.

Layout por bloco (Block Guide §7.1):

```
base = 4*i   (i = índice do bloco)
mem[base+0] = bits [127:96]
mem[base+1] = bits [ 95:64]
mem[base+2] = bits [ 63:32]
mem[base+3] = bits [ 31: 0]
```

Palavras além da região ativa (`>= 4*N`) ficam em **zero** nos arquivos
input **e** expected. A TB pode verificar que o DUT não corrompe essa
área (higiene).

**CTR:** `CTR_enc_*` e `CTR_dec_*` são **idênticos por construção** —
o bit `DECRYPT` é ignorado (§8.2). A TB deve conseguir rodar os dois e
obter o mesmo resultado; isso prova que `DECRYPT` não afeta CTR.


### `test_cases.svh`

Include SV com os 18 casos válidos e 7 inválidos. Uso na TB:

```systemverilog
`include "tb/vectors/test_cases.svh"

initial begin
    for (int i = 0; i < NUM_VALID_CASES; i++) begin
        $readmemh(VALID_CASES[i].input_file, mem);
        // configurar mode/decrypt/num_blocks = VALID_CASES[i].* ...
    end
end
```

### `invalid_configs.json`

Configs que devem produzir `ERROR=1` sem processar:

| mode | decrypt | num_blocks | motivo |
|------|---------|------------|--------|
| 000  | 0       | 0          | NUM_BLOCKS abaixo do mínimo |
| 000  | 0       | 257        | NUM_BLOCKS acima do máximo |
| 110  | 0       | 1          | MODE reservado |
| 111  | 0       | 1          | MODE reservado |
| 010  | 0       | 1          | PCBC não implementado (Semana 10) |
| 011  | 0       | 1          | CFB não implementado (Semana 10) |
| 100  | 0       | 1          | OFB não implementado (Semana 10) |

## Configuração fixa dos vetores

| Parâmetro | Valor |
|-----------|-------|
| KEY       | `000102030405060708090a0b0c0d0e0f` |
| IV        | `101112131415161718191a1b1c1d1e1f` |
| COUNTER   | `DEADBEEFCAFEBABE` |
| SEED      | `minisoc_aes_semana6` |

Inputs são determinísticos (SHA-256 do índice do bloco), então os
vetores são reproduzíveis byte a byte em qualquer máquina.

## Comportamento dos modos

- **ECB (000):** `C[i] = AES_enc(P[i])` ou `P[i] = AES_dec(C[i])`
- **CBC (001):** `C[i] = AES_enc(P[i] XOR C[i-1])` / `P[i] = AES_dec(C[i]) XOR C[i-1]` com `C[-1] = IV`
- **CTR (101):** `keystream[i] = AES_enc(IV XOR zext64(COUNTER+i))`; `C[i] = P[i] XOR keystream[i]`. `DECRYPT` é ignorado (§8.2).
