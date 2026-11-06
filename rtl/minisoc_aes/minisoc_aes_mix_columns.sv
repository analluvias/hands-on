module minisoc_aes_mix_columns (
    input  logic [127:0] state_in,
    output logic [127:0] state_out
);

    // Função de multiplicação por 0x02 no Galois Field GF(2^8)
    function automatic logic [7:0] xtime(input logic [7:0] b);
        return (b[7] == 1'b1) ? ((b << 1) ^ 8'h1b) : (b << 1);
    endfunction

    // Função para misturar 1 coluna (4 bytes)
    function automatic logic [31:0] mix_one_column(input logic [31:0] col_in);
        logic [7:0] s0, s1, s2, s3;
        logic [7:0] s0_out, s1_out, s2_out, s3_out;

        s0 = col_in[31:24];
        s1 = col_in[23:16];
        s2 = col_in[15:8];
        s3 = col_in[7:0];

        // s'0 = ({02} * s0) ^ ({03} * s1) ^ s2 ^ s3
        s0_out = xtime(s0) ^ (xtime(s1) ^ s1) ^ s2 ^ s3;
        // s'1 = s0 ^ ({02} * s1) ^ ({03} * s2) ^ s3
        s1_out = s0 ^ xtime(s1) ^ (xtime(s2) ^ s2) ^ s3;
        // s'2 = s0 ^ s1 ^ ({02} * s2) ^ ({03} * s3)
        s2_out = s0 ^ s1 ^ xtime(s2) ^ (xtime(s3) ^ s3);
        // s'3 = ({03} * s0) ^ s1 ^ s2 ^ ({02} * s3)
        s3_out = (xtime(s0) ^ s0) ^ s1 ^ s2 ^ xtime(s3);

        return {s0_out, s1_out, s2_out, s3_out};
    endfunction

    // Aplicação às 4 colunas (Words 0 a 3) do Estado de 128 bits
    assign state_out = {
        mix_one_column(state_in[127:96]), // Coluna 0
        mix_one_column(state_in[95:64]),  // Coluna 1
        mix_one_column(state_in[63:32]),  // Coluna 2
        mix_one_column(state_in[31:0])    // Coluna 3
    };

endmodule