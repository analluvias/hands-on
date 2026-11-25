#!/usr/bin/env python3
# =============================================================================
# aes_ref_model.py
#
# Modelo de referência do MiniSoC AES e gerador de vetores para o testbench
# da Semana 6 (Issue 3).
#
# Gera:
#   - tb/vectors/{MODE}_{DIR}_{N}_input.mem    (18 arquivos)
#   - tb/vectors/{MODE}_{DIR}_{N}_expected.mem (18 arquivos)
#   - tb/vectors/test_cases.svh                (metadados p/ TB)
#   - tb/vectors/invalid_configs.json          (configs que devem dar ERROR)
#   - tb/vectors/README.md                     (resumo do diretório)
#
# Cobre apenas ECB (000), CBC (001) e CTR (101) — sem PCBC/CFB/OFB.
#
# Uso:
#   python3 tools/aes_ref_model.py
#   python3 tools/aes_ref_model.py --out-dir /caminho/custom
#
# Dependências: nenhuma (AES-128 puro Python).
# =============================================================================

import argparse
import hashlib
import json
from pathlib import Path

# =============================================================================
# AES-128 (FIPS-197) — implementação de referência, pura Python
# =============================================================================

SBOX = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
]
INV_SBOX = [0] * 256
for i, v in enumerate(SBOX):
    INV_SBOX[v] = i
RCON = [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]


def _xtime(a):
    b = (a << 1) & 0x1FF
    if b & 0x100:
        b ^= 0x11B
    return b & 0xFF


def _mul(a, b):
    r = 0
    for _ in range(8):
        if b & 1:
            r ^= a
        a = _xtime(a)
        b >>= 1
    return r


def _expand_key(key):
    w = [list(key[4 * i:4 * i + 4]) for i in range(4)]
    for i in range(4, 44):
        t = list(w[i - 1])
        if i % 4 == 0:
            t = t[1:] + t[:1]
            t = [SBOX[b] for b in t]
            t[0] ^= RCON[i // 4]
        w.append([w[i - 4][j] ^ t[j] for j in range(4)])
    return [bytes(sum(w[4 * r:4 * r + 4], [])) for r in range(11)]


def _add_round_key(s, k):
    return bytes(a ^ b for a, b in zip(s, k))


def _sub_bytes(s):
    return bytes(SBOX[b] for b in s)


def _inv_sub_bytes(s):
    return bytes(INV_SBOX[b] for b in s)


def _shift_rows(s):
    return bytes([
        s[0], s[5], s[10], s[15],
        s[4], s[9], s[14], s[3],
        s[8], s[13], s[2], s[7],
        s[12], s[1], s[6], s[11],
    ])


def _inv_shift_rows(s):
    return bytes([
        s[0], s[13], s[10], s[7],
        s[4], s[1], s[14], s[11],
        s[8], s[5], s[2], s[15],
        s[12], s[9], s[6], s[3],
    ])


def _mix_columns(s):
    out = bytearray(16)
    for c in range(4):
        col = s[4 * c:4 * c + 4]
        out[4 * c + 0] = _mul(col[0], 2) ^ _mul(col[1], 3) ^ col[2] ^ col[3]
        out[4 * c + 1] = col[0] ^ _mul(col[1], 2) ^ _mul(col[2], 3) ^ col[3]
        out[4 * c + 2] = col[0] ^ col[1] ^ _mul(col[2], 2) ^ _mul(col[3], 3)
        out[4 * c + 3] = _mul(col[0], 3) ^ col[1] ^ col[2] ^ _mul(col[3], 2)
    return bytes(out)


def _inv_mix_columns(s):
    out = bytearray(16)
    for c in range(4):
        col = s[4 * c:4 * c + 4]
        out[4 * c + 0] = _mul(col[0], 14) ^ _mul(col[1], 11) ^ _mul(col[2], 13) ^ _mul(col[3], 9)
        out[4 * c + 1] = _mul(col[0], 9) ^ _mul(col[1], 14) ^ _mul(col[2], 11) ^ _mul(col[3], 13)
        out[4 * c + 2] = _mul(col[0], 13) ^ _mul(col[1], 9) ^ _mul(col[2], 14) ^ _mul(col[3], 11)
        out[4 * c + 3] = _mul(col[0], 11) ^ _mul(col[1], 13) ^ _mul(col[2], 9) ^ _mul(col[3], 14)
    return bytes(out)


def aes128_encrypt(key, block):
    rk = _expand_key(key)
    s = _add_round_key(block, rk[0])
    for r in range(1, 10):
        s = _mix_columns(_shift_rows(_sub_bytes(s)))
        s = _add_round_key(s, rk[r])
    s = _shift_rows(_sub_bytes(s))
    return _add_round_key(s, rk[10])


def aes128_decrypt(key, block):
    rk = _expand_key(key)
    s = _add_round_key(block, rk[10])
    for r in range(9, 0, -1):
        s = _inv_mix_columns(_add_round_key(_inv_sub_bytes(_inv_shift_rows(s)), rk[r]))
    s = _inv_sub_bytes(_inv_shift_rows(s))
    return _add_round_key(s, rk[0])


def _self_test():
    """Aborta se AES-128 divergir do vetor FIPS-197 §C.1."""
    pt = bytes.fromhex("00112233445566778899aabbccddeeff")
    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    ct = bytes.fromhex("69c4e0d86a7b0430d8cdb78070b4c55a")
    assert aes128_encrypt(key, pt) == ct, "AES-128 encrypt self-test failed"
    assert aes128_decrypt(key, ct) == pt, "AES-128 decrypt self-test failed"
    print("[OK] AES-128 self-test (FIPS-197 §C.1) passed")


# =============================================================================
# Configuração fixa do MiniSoC AES
# =============================================================================

KEY = bytes.fromhex("000102030405060708090a0b0c0d0e0f")  # FIPS-197 test key
IV = bytes.fromhex("101112131415161718191a1b1c1d1e1f")
COUNTER = 0xDEADBEEFCAFEBABE
SEED = "minisoc_aes_semana6"
NUM_WORDS = 1024

MODES = [("ECB", 0b000), ("CBC", 0b001), ("CTR", 0b101)]
DIRECTIONS = [("enc", 0), ("dec", 1)]
SIZES = [1, 2, 256]

INVALID_CONFIGS = [
    {"mode": 0b000, "decrypt": 0, "num_blocks": 0,
     "reason": "NUM_BLOCKS=0 below minimum (valid: 1..256)"},
    {"mode": 0b000, "decrypt": 0, "num_blocks": 257,
     "reason": "NUM_BLOCKS=257 above maximum (valid: 1..256)"},
    {"mode": 0b110, "decrypt": 0, "num_blocks": 1,
     "reason": "MODE=110 reserved"},
    {"mode": 0b111, "decrypt": 0, "num_blocks": 1,
     "reason": "MODE=111 reserved"},
    {"mode": 0b010, "decrypt": 0, "num_blocks": 1,
     "reason": "MODE=010 PCBC not supported in v1.0 (Semana 10)"},
    {"mode": 0b011, "decrypt": 0, "num_blocks": 1,
     "reason": "MODE=011 CFB not supported in v1.0 (Semana 10)"},
    {"mode": 0b100, "decrypt": 0, "num_blocks": 1,
     "reason": "MODE=100 OFB not supported in v1.0 (Semana 10)"},
]


# =============================================================================
# Geração de blocos e processamento por modo
# =============================================================================

def gen_block(index):
    """16 bytes determinísticos — reproduzível em qualquer máquina."""
    return hashlib.sha256(f"{SEED}_block_{index}".encode()).digest()[:16]


def xor_bytes(a, b):
    return bytes(x ^ y for x, y in zip(a, b))


def ctr_128block(ctr):
    """Contador de 64 bits zero-extendido para 128 bits (§8.2)."""
    return b"\x00" * 8 + ctr.to_bytes(8, "big")


def process(mode, decrypt, blocks):
    """Aplica o modo ao longo dos blocos conforme §8.2."""
    if mode == 0b000:  # ECB
        return [aes128_decrypt(KEY, b) if decrypt else aes128_encrypt(KEY, b)
                for b in blocks]

    if mode == 0b001:  # CBC
        out, prev = [], IV
        for b in blocks:
            if decrypt:
                out.append(xor_bytes(aes128_decrypt(KEY, b), prev))
                prev = b
            else:
                c = aes128_encrypt(KEY, xor_bytes(b, prev))
                out.append(c)
                prev = c
        return out

    if mode == 0b101:  # CTR — primitive sempre encrypt (§8.2)
        out, ctr = [], COUNTER
        for b in blocks:
            ks = aes128_encrypt(KEY, xor_bytes(IV, ctr_128block(ctr)))
            out.append(xor_bytes(b, ks))
            ctr = (ctr + 1) & 0xFFFFFFFFFFFFFFFF
        return out

    raise ValueError(f"Modo não suportado: {mode:03b}")


# =============================================================================
# Layout de memória (§7.1) e escrita de arquivos
# =============================================================================

def blocks_to_memory(blocks):
    """Empacota blocos de 16 bytes em array de 1024 palavras (§7.1)."""
    mem = [0] * NUM_WORDS
    for i, b in enumerate(blocks):
        if 4 * i + 3 >= NUM_WORDS:
            break
        mem[4 * i + 0] = int.from_bytes(b[0:4], "big")
        mem[4 * i + 1] = int.from_bytes(b[4:8], "big")
        mem[4 * i + 2] = int.from_bytes(b[8:12], "big")
        mem[4 * i + 3] = int.from_bytes(b[12:16], "big")
    return mem


def write_mem_file(path, mem):
    with open(path, "w") as f:
        for w in mem:
            f.write(f"{w:08x}\n")


def write_test_cases_svh(path, cases, invalid):
    """Gera include SV consumido pela TB (Issue #4)."""
    lines = [
        "// =============================================================================",
        "// test_cases.svh — Auto-gerado por tools/aes_ref_model.py. NÃO EDITAR.",
        "//",
        "// Uso na TB:",
        '//   `include "tb/vectors/test_cases.svh"',
        "//   for (int i = 0; i < NUM_VALID_CASES; i++) begin",
        "//       // VALID_CASES[i].mode / .decrypt / .num_blocks / .input_file / .expected_file",
        "//   end",
        "// =============================================================================",
        "",
        f"localparam int NUM_VALID_CASES = {len(cases)};",
        "",
        "typedef struct {",
        "    logic [2:0] mode;",
        "    logic       decrypt;",
        "    logic [8:0] num_blocks;",
        "    string      input_file;",
        "    string      expected_file;",
        "} aes_test_case_t;",
        "",
        "localparam aes_test_case_t VALID_CASES[NUM_VALID_CASES] = '{",
    ]
    for c in cases:
        lines.append(
            f'    \'{{3\'b{c["mode"]:03b}, 1\'b{c["decrypt"]}, 9\'d{c["num_blocks"]}, '
            f'"{c["input_file"]}", "{c["expected_file"]}"}},'
        )
    lines.append("};")
    lines.append("")
    lines.append(f"localparam int NUM_INVALID_CASES = {len(invalid)};")
    lines.append("")
    lines.append("typedef struct {")
    lines.append("    logic [2:0] mode;")
    lines.append("    logic       decrypt;")
    lines.append("    logic [8:0] num_blocks;")
    lines.append("} aes_invalid_case_t;")
    lines.append("")
    lines.append("localparam aes_invalid_case_t INVALID_CASES[NUM_INVALID_CASES] = '{")
    for c in invalid:
        lines.append(
            f'    \'{{3\'b{c["mode"]:03b}, 1\'b{c["decrypt"]}, 9\'d{c["num_blocks"]}}},'
        )
    lines.append("};")
    lines.append("")

    with open(path, "w") as f:
        f.write("\n".join(lines))


# =============================================================================
# main
# =============================================================================

def main():
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out-dir", default=str(repo_root / "tb" / "vectors"),
                        help="Diretório de saída (default: <repo>/tb/vectors)")
    args = parser.parse_args()

    _self_test()

    out = Path(args.out_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)
    print(f"[INFO] out-dir = {out}")

    cases = []
    for mode_name, mode_val in MODES:
        for dir_name, decrypt_val in DIRECTIONS:
            for num_blocks in SIZES:
                blocks = [gen_block(i) for i in range(num_blocks)]
                result = process(mode_val, decrypt_val, blocks)

                in_mem = blocks_to_memory(blocks)
                out_mem = blocks_to_memory(result)

                base = f"{mode_name}_{dir_name}_{num_blocks}"
                in_path = out / f"{base}_input.mem"
                out_path = out / f"{base}_expected.mem"

                write_mem_file(in_path, in_mem)
                write_mem_file(out_path, out_mem)

                rel_in = in_path.relative_to(repo_root).as_posix()
                rel_out = out_path.relative_to(repo_root).as_posix()

                cases.append({
                    "name": base,
                    "mode": mode_val,
                    "mode_name": mode_name,
                    "decrypt": decrypt_val,
                    "direction": dir_name,
                    "num_blocks": num_blocks,
                    "input_file": rel_in,
                    "expected_file": rel_out,
                })
                print(f"  [OK] {base}: {rel_in} / {rel_out}")

    write_test_cases_svh(out / "test_cases.svh", cases, INVALID_CONFIGS)
    print(f"[OK] test_cases.svh ({len(cases)} valid + {len(INVALID_CONFIGS)} invalid)")

    with open(out / "invalid_configs.json", "w") as f:
        json.dump(INVALID_CONFIGS, f, indent=2)
    print(f"[OK] invalid_configs.json")

    with open(out / "index.json", "w") as f:
        json.dump({
            "key": KEY.hex(),
            "iv": IV.hex(),
            "counter": f"{COUNTER:016x}",
            "seed": SEED,
            "num_words": NUM_WORDS,
            "modes_implemented": ["ECB (000)", "CBC (001)", "CTR (101)"],
            "modes_not_implemented": ["PCBC (010)", "CFB (011)", "OFB (100)"],
            "cases": cases,
            "invalid_cases": INVALID_CONFIGS,
        }, f, indent=2)
    print(f"[OK] index.json")

    readme = f"""# tb/vectors — Auto-generated

Gerado por `tools/aes_ref_model.py`. **Não editar manualmente.**

- Configuração fixa: KEY=`{KEY.hex()}`, IV=`{IV.hex()}`, COUNTER=`{COUNTER:016x}`
- {len(cases)} casos válidos × 2 arquivos (input + expected) = {len(cases) * 2} `.mem` files
- {len(INVALID_CONFIGS)} casos inválidos em `invalid_configs.json`
- Lista de casos consumível por SV: `test_cases.svh`

Regenerar:

    python3 tools/aes_ref_model.py
"""
    with open(out / "README.md", "w") as f:
        f.write(readme)

    print(f"\nDone: {len(cases)} valid + {len(INVALID_CONFIGS)} invalid cases")


if __name__ == "__main__":
    main()