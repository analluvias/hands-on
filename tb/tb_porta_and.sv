module tb_porta_and;
    logic a;
    logic b;
    logic y;

    porta_and dut (
        .a(a),
        .b(b),
        .y(y)
    );

    initial begin
        $display("Iniciando a simulação da Porta AND...");
        a = 0; b = 0; #10; $display("a=%b, b=%b -> y=%b", a, b, y);
        a = 0; b = 1; #10; $display("a=%b, b=%b -> y=%b", a, b, y);
        a = 1; b = 0; #10; $display("a=%b, b=%b -> y=%b", a, b, y);
        a = 1; b = 1; #10; $display("a=%b, b=%b -> y=%b", a, b, y);
        $display("Simulação concluída!");
        $finish;
    end
endmodule