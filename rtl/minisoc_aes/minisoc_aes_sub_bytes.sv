module minisoc_aes_sub_bytes (
    input  logic [127:0] state_in,
    output logic [127:0] state_out
);

    // Instanciação de 16 S-Boxes em paralelo
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_sbox
            minisoc_aes_sbox u_sbox (
                .in  (state_in [127 - 8*i -: 8]),
                .out (state_out[127 - 8*i -: 8])
            );
        end
    endgenerate

endmodule