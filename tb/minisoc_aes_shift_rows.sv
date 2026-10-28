logic [127:0] subbytes_out;
logic [127:0] shiftrows_out;

minisoc_aes_shift_rows dut_shift_rows (
    .state_in (subbytes_out),
    .state_out(shiftrows_out)
);

initial begin
    subbytes_out = 128'hd42711aee0bf98f1b8b45de51e415230;
    #1;
    
    assert (shiftrows_out == 128'hd4bf5d30e0b452aeb84111f11e2798e5)
        else $error("Erro em ShiftRows: obtido %h, esperado d4bf5d30e0b452aeb84111f11e2798e5", shiftrows_out);
end