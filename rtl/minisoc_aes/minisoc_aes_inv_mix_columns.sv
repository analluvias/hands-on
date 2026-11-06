module minisoc_aes_inv_mix_columns (
    input  logic [127:0] state_in,
    output logic [127:0] state_out
);

    // Multiplicação básica por 0x02 em GF(2^8) (xtime)
    function automatic logic [7:0] xtime(input logic [7:0] b);
        return (b[7] == 1'b1) ? ((b << 1) ^ 8'h1b) : (b << 1);
    endfunction

    // Funções auxiliares para multiplicação pelas constantes FIPS-197
    function automatic logic [7:0] mul_09(input logic [7:0] b);
        logic [7:0] x2, x4, x8;
        x2 = xtime(b);
        x4 = xtime(x2);
        x8 = xtime(x4);
        return (x8 ^ b);
    endfunction

    function automatic logic [7:0] mul_0b(input logic [7:0] b);
        logic [7:0] x2, x4, x8;
        x2 = xtime(b);
        x4 = xtime(x2);
        x8 = xtime(x4);
        return (x8 ^ x2 ^ b);
    endfunction

    function automatic logic [7:0] mul_0d(input logic [7:0] b);
        logic [7:0] x2, x4, x8;
        x2 = xtime(b);
        x4 = xtime(x2);
        x8 = xtime(x4);
        return (x8 ^ x4 ^ b);
    endfunction

    function automatic logic [7:0] mul_0e(input logic [7:0] b);
        logic [7:0] x2, x4, x8;
        x2 = xtime(b);
        x4 = xtime(x2);
        x8 = xtime(x4);
        return (x8 ^ x4 ^ x2);
    endfunction

    // Transformação InvMixColumns em 1 coluna (4 bytes de 32 bits)
    function automatic logic [31:0] inv_mix_one_column(input logic [31:0] col_in);
        logic [7:0] s0, s1, s2, s3;
        logic [7:0] s0_out, s1_out, s2_out, s3_out;

        s0 = col_in[31:24];
        s1 = col_in[23:16];
        s2 = col_in[15:8];
        s3 = col_in[7:0];

        // Multiplicação matricial sobre GF(2^8) conforme FIPS-197
        s0_out = mul_0e(s0) ^ mul_0b(s1) ^ mul_0d(s2) ^ mul_09(s3);
        s1_out = mul_09(s0) ^ mul_0e(s1) ^ mul_0b(s2) ^ mul_0d(s3);
        s2_out = mul_0d(s0) ^ mul_09(s1) ^ mul_0e(s2) ^ mul_0b(s3);
        s3_out = mul_0b(s0) ^ mul_0d(s1) ^ mul_09(s2) ^ mul_0e(s3);

        return {s0_out, s1_out, s2_out, s3_out};
    endfunction

    // Aplicação às 4 colunas (Words 0 a 3) do estado de 128 bits
    assign state_out = {
        inv_mix_one_column(state_in[127:96]), // Coluna 0
        inv_mix_one_column(state_in[95:64]),  // Coluna 1
        inv_mix_one_column(state_in[63:32]),  // Coluna 2
        inv_mix_one_column(state_in[31:0])    // Coluna 3
    };

endmodule