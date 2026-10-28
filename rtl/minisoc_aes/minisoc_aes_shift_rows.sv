module minisoc_aes_shift_rows (
    input  logic [127:0] state_in,
    output logic [127:0] state_out
);

    assign state_out = {
        // Word 0 (saída)
        state_in[127:120], // Byte 0  <- s0,0 (in Byte 0)
        state_in[ 87: 80], // Byte 1  <- s1,1 (in Byte 5)
        state_in[ 47: 40], // Byte 2  <- s2,2 (in Byte 10)
        state_in[  7:  0], // Byte 3  <- s3,3 (in Byte 15)

        // Word 1 (saída)
        state_in[ 95: 88], // Byte 4  <- s0,1 (in Byte 4)
        state_in[ 55: 48], // Byte 5  <- s1,2 (in Byte 9)
        state_in[ 15:  8], // Byte 6  <- s2,3 (in Byte 14)
        state_in[103: 96], // Byte 7  <- s3,0 (in Byte 3)

        // Word 2 (saída)
        state_in[ 63: 56], // Byte 8  <- s0,2 (in Byte 8)
        state_in[ 23: 16], // Byte 9  <- s1,3 (in Byte 13)
        state_in[111:104], // Byte 10 <- s2,0 (in Byte 2)
        state_in[ 71: 64], // Byte 11 <- s3,1 (in Byte 7)

        // Word 3 (saída)
        state_in[ 31: 24], // Byte 12 <- s0,3 (in Byte 12)
        state_in[119:112], // Byte 13 <- s1,0 (in Byte 1)
        state_in[ 79: 72], // Byte 14 <- s2,1 (in Byte 6)
        state_in[ 39: 32]  // Byte 15 <- s3,2 (in Byte 11)
    };

endmodule