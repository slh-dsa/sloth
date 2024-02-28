//  keccak_round.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Purely combinatorial ("stackable") logic for Keccak-f1600 (of "SHA3").

`include "config.vh"
`ifdef SLOTH_KECCAK

module keccak_round(
    output wire [1599:0] s_o,           //  state out
    output wire [7:0]    r_o,           //  rc out
    input wire  [1599:0] s_i,           //  state in
    input wire  [7:0]    r_i            //  rc in
);
    //  Theta (3.2.1), Algorithm 1

    //  Step 1
    wire [319:0]    c_w =   (   s_i[ 319:   0] ^
                                s_i[ 639: 320] ^
                                s_i[ 959: 640] ^
                                s_i[1279: 960] ^
                                s_i[1599:1280]  );

    //  Step 2
    wire [319:0]    d_w =   {   c_w[255:  0], c_w[319:256] } ^
                            {   c_w[ 62:  0], c_w[ 63],
                                c_w[318:256], c_w[319],
                                c_w[254:192], c_w[255],
                                c_w[190:128], c_w[191],
                                c_w[126: 64], c_w[127] };

    //  Step 3
    wire [1599:0]   th_w =  s_i ^ { d_w, d_w, d_w, d_w, d_w };

    //  Rho (3.2.2), Pi (3.2.3), Combined Algorithms 2 and 3

    wire [1599:0]   rp_w =  {   th_w[1405:1344], th_w[1407:1406],
                                th_w[ 982: 960], th_w[1023: 983],
                                th_w[ 920: 896], th_w[ 959: 921],
                                th_w[ 520: 512], th_w[ 575: 521],
                                th_w[ 129: 128], th_w[ 191: 130],
                                th_w[1479:1472], th_w[1535:1480],
                                th_w[1136:1088], th_w[1151:1137],
                                th_w[ 757: 704], th_w[ 767: 758],
                                th_w[ 347: 320], th_w[ 383: 348],
                                th_w[ 292: 256], th_w[ 319: 293],
                                th_w[1325:1280], th_w[1343:1326],
                                th_w[1271:1216], th_w[1279:1272],
                                th_w[ 870: 832], th_w[ 895: 871],
                                th_w[ 505: 448], th_w[ 511: 506],
                                th_w[ 126:  64], th_w[ 127: 127],
                                th_w[1410:1408], th_w[1471:1411],
                                th_w[1042:1024], th_w[1087:1043],
                                th_w[ 700: 640], th_w[ 703: 701],
                                th_w[ 619: 576], th_w[ 639: 620],
                                th_w[ 227: 192], th_w[ 255: 228],
                                th_w[1585:1536], th_w[1599:1586],
                                th_w[1194:1152], th_w[1215:1195],
                                th_w[ 788: 768], th_w[ 831: 789],
                                th_w[ 403: 384], th_w[ 447: 404],
                                th_w[  63:   0] };

    //  Chi (3.2.4), Algorithm 4

    wire [1599:0]   chi_w = rp_w ^ {
                            {   rp_w[1407:1280], rp_w[1599:1408] } &~
                            {   rp_w[1343:1280], rp_w[1599:1344] },
                            {   rp_w[1087: 960], rp_w[1279:1088] } &~
                            {   rp_w[1023: 960], rp_w[1279:1024] },
                            {   rp_w[ 767: 640], rp_w[ 959: 768] } &~
                            {   rp_w[ 703: 640], rp_w[ 959: 704] },
                            {   rp_w[ 447: 320], rp_w[ 639: 448] } &~
                            {   rp_w[ 383: 320], rp_w[ 639: 384] },
                            {   rp_w[ 127:   0], rp_w[ 319: 128] } &~
                            {   rp_w[  63:   0], rp_w[ 319:  64] }  };

    //  Iota (3.2.5)

    //  This matrix implements 7 steps of the LFSR described in Algorithm 5;
    //  converted from Galois to Fibonacci representation and combined.
    assign  r_o =   ({8{r_i[0]}} & 8'h1A) ^ ({8{r_i[1]}} & 8'h34) ^
                    ({8{r_i[2]}} & 8'h68) ^ ({8{r_i[3]}} & 8'hD0) ^
                    ({8{r_i[4]}} & 8'hBA) ^ ({8{r_i[5]}} & 8'h6E) ^
                    ({8{r_i[6]}} & 8'hC6) ^ ({8{r_i[7]}} & 8'h8D);

    //  Expands low 7 bits into 64 words for lane (0,) as per Algorithm 6.
    assign  s_o =   {   chi_w[1599:64],
                            r_i[6] ^ chi_w[63], chi_w[62:32],
                            r_i[5] ^ chi_w[31], chi_w[30:16],
                            r_i[4] ^ chi_w[15], chi_w[14: 8],
                            r_i[3] ^ chi_w[ 7], chi_w[ 6: 4],
                            r_i[2] ^ chi_w[ 3], chi_w[ 2],
                            r_i[1] ^ chi_w[ 1],
                            r_i[0] ^ chi_w[ 0]  };

endmodule

`endif
