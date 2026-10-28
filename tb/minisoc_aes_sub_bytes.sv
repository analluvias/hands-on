logic [127:0] state_in;
logic [127:0] state_out;

minisoc_aes_sub_bytes dut_sub_bytes (
    .state_in (state_in),
    .state_out(state_out)
);

initial begin
    state_in = 128'h193de3bea0f4e22b9ac68d2ae9f84808;
    #1; // tempo combinacional
    
    assert (state_out == 128'hd42711aee0bf98f1b8b45de51e415230)
        else $error("Erro no SubBytes: obtido %h, esperado d42711aee0bf98f1b8b45de51e415230", state_out);
end