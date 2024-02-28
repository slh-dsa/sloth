//  kecti3_sloth.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Masked Keccak (3-Share Threshold Implementation)
//  This is even more experimental than the rest -- work in progress.

`include "config.vh"
`ifdef SLOTH_KECTI3

//  Theta (3.2.1), Algorithm 1

module kecti3_lin(
    output wire [1599:0] l_o,
    input wire  [1599:0] x_i
);
    //  Step 1
    wire    [319:0] c_w =   x_i[ 319:   0] ^
                            x_i[ 639: 320] ^
                            x_i[ 959: 640] ^
                            x_i[1279: 960] ^
                            x_i[1599:1280];

    //  Step 2
    wire    [319:0] d_w =   {   c_w[255:  0], c_w[319:256]  } ^
                            {   c_w[ 62:  0], c_w[ 63],
                                c_w[318:256], c_w[319],
                                c_w[254:192], c_w[255],
                                c_w[190:128], c_w[191],
                                c_w[126: 64], c_w[127] };

    //  Step 3
    wire    [1599:0] t_w =  x_i ^ { d_w, d_w, d_w, d_w, d_w };

    //  Rho (3.2.2), Pi (3.2.3), Combined Algorithms 2 and 3

    assign  l_o     =   {   t_w[1405:1344], t_w[1407:1406],
                            t_w[ 982: 960], t_w[1023: 983],
                            t_w[ 920: 896], t_w[ 959: 921],
                            t_w[ 520: 512], t_w[ 575: 521],
                            t_w[ 129: 128], t_w[ 191: 130],
                            t_w[1479:1472], t_w[1535:1480],
                            t_w[1136:1088], t_w[1151:1137],
                            t_w[ 757: 704], t_w[ 767: 758],
                            t_w[ 347: 320], t_w[ 383: 348],
                            t_w[ 292: 256], t_w[ 319: 293],
                            t_w[1325:1280], t_w[1343:1326],
                            t_w[1271:1216], t_w[1279:1272],
                            t_w[ 870: 832], t_w[ 895: 871],
                            t_w[ 505: 448], t_w[ 511: 506],
                            t_w[ 126:  64], t_w[ 127: 127],
                            t_w[1410:1408], t_w[1471:1411],
                            t_w[1042:1024], t_w[1087:1043],
                            t_w[ 700: 640], t_w[ 703: 701],
                            t_w[ 619: 576], t_w[ 639: 620],
                            t_w[ 227: 192], t_w[ 255: 228],
                            t_w[1585:1536], t_w[1599:1586],
                            t_w[1194:1152], t_w[1215:1195],
                            t_w[ 788: 768], t_w[ 831: 789],
                            t_w[ 403: 384], t_w[ 447: 404],
                            t_w[  63:   0] };
endmodule

//  Pairwise Threshold Chi

module kecti3_tchi(
    output wire [319:0] f_o,
    input wire  [319:0] x_i,
    input wire  [319:0] y_i
);

    wire [319:0] x1_w = { x_i[ 63:  0], x_i[319: 64] };
    wire [319:0] x2_w = { x_i[127:  0], x_i[319:128] };
    wire [319:0] y1_w = { y_i[ 63:  0], y_i[319: 64] };
    wire [319:0] y2_w = { y_i[127:  0], y_i[319:128] };

    assign f_o = x_i ^ ( ~x1_w & x2_w ) ^ ( x1_w & y2_w ) ^ ( y1_w & x2_w );

endmodule

//  threshold round

module kecti3_round (
    output wire [1599:0] a_o,           //  shares out
    output wire [1599:0] b_o,
    output wire [1599:0] c_o,
    input wire  [1599:0] a_i,           //  shares in
    input wire  [1599:0] b_i,
    input wire  [1599:0] c_i,
    input wire  [7:0]    r_i            //  rc in
);

    //  Linear layers for shares A, B, C
    wire    [1599:0]    la_w, lb_w, lc_w;
    kecti3_lin  lin_a   (   .l_o(la_w), .x_i(a_i) );
    kecti3_lin  lin_b   (   .l_o(lb_w), .x_i(b_i) );
    kecti3_lin  lin_c   (   .l_o(lc_w), .x_i(c_i) );

    //  Nonlinear ops on shares A, B, C
    wire    [1599:0]    a_w;            //  share without rc
    genvar i;

    generate
        for (i = 0; i < 1600; i = i + 320) begin
            kecti3_tchi tchi_a  (   .f_o(  a_w[319 + i: i]  ),
                                    .x_i( la_w[319 + i: i]  ),
                                    .y_i( lb_w[319 + i: i]  )   );
            kecti3_tchi tchi_b  (   .f_o(  b_o[319 + i: i]  ),
                                    .x_i( lb_w[319 + i: i]  ),
                                    .y_i( lc_w[319 + i: i]  )   );
            kecti3_tchi tchi_c  (   .f_o(  c_o[319 + i: i]  ),
                                    .x_i( lc_w[319 + i: i]  ),
                                    .y_i( la_w[319 + i: i]  )   );
        end
    endgenerate

    //  Iota: spread round constant bits into least signigicant word
    assign  a_o =   {   a_w[1599:64],
                        r_i[6] ^ a_w[63], a_w[62:32],
                        r_i[5] ^ a_w[31], a_w[30:16],
                        r_i[4] ^ a_w[15], a_w[14: 8],
                        r_i[3] ^ a_w[ 7], a_w[ 6: 4],
                        r_i[2] ^ a_w[ 3], a_w[ 2],
                        r_i[1] ^ a_w[ 1],
                        r_i[0] ^ a_w[ 0]    };
endmodule

`endif
