//  sha512_round.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Purely combinatorial ("stackable") logic for a SHA2-384/512 round.
//  Updates the state and the message block. No final chaining addition.

`include "config.vh"
`ifdef SLOTH_SHA512

module sha512_round(
    output  wire [511:0]    h_o,        //  state out
    output  wire [1023:0]   m_o,        //  message out
    input   wire [511:0]    h_i,        //  state in
    input   wire [1023:0]   m_i,        //  message in
    input   wire [6:0]      t_i         //  round 0..79
);
    //  round constants
    reg [63:0] k_w;

    always@(t_i) begin
        case(t_i)
            7'h00: k_w = 64'h428a2f98d728ae22;
            7'h01: k_w = 64'h7137449123ef65cd;
            7'h02: k_w = 64'hb5c0fbcfec4d3b2f;
            7'h03: k_w = 64'he9b5dba58189dbbc;
            7'h04: k_w = 64'h3956c25bf348b538;
            7'h05: k_w = 64'h59f111f1b605d019;
            7'h06: k_w = 64'h923f82a4af194f9b;
            7'h07: k_w = 64'hab1c5ed5da6d8118;
            7'h08: k_w = 64'hd807aa98a3030242;
            7'h09: k_w = 64'h12835b0145706fbe;
            7'h0A: k_w = 64'h243185be4ee4b28c;
            7'h0B: k_w = 64'h550c7dc3d5ffb4e2;
            7'h0C: k_w = 64'h72be5d74f27b896f;
            7'h0D: k_w = 64'h80deb1fe3b1696b1;
            7'h0E: k_w = 64'h9bdc06a725c71235;
            7'h0F: k_w = 64'hc19bf174cf692694;
            7'h10: k_w = 64'he49b69c19ef14ad2;
            7'h11: k_w = 64'hefbe4786384f25e3;
            7'h12: k_w = 64'h0fc19dc68b8cd5b5;
            7'h13: k_w = 64'h240ca1cc77ac9c65;
            7'h14: k_w = 64'h2de92c6f592b0275;
            7'h15: k_w = 64'h4a7484aa6ea6e483;
            7'h16: k_w = 64'h5cb0a9dcbd41fbd4;
            7'h17: k_w = 64'h76f988da831153b5;
            7'h18: k_w = 64'h983e5152ee66dfab;
            7'h19: k_w = 64'ha831c66d2db43210;
            7'h1A: k_w = 64'hb00327c898fb213f;
            7'h1B: k_w = 64'hbf597fc7beef0ee4;
            7'h1C: k_w = 64'hc6e00bf33da88fc2;
            7'h1D: k_w = 64'hd5a79147930aa725;
            7'h1E: k_w = 64'h06ca6351e003826f;
            7'h1F: k_w = 64'h142929670a0e6e70;
            7'h20: k_w = 64'h27b70a8546d22ffc;
            7'h21: k_w = 64'h2e1b21385c26c926;
            7'h22: k_w = 64'h4d2c6dfc5ac42aed;
            7'h23: k_w = 64'h53380d139d95b3df;
            7'h24: k_w = 64'h650a73548baf63de;
            7'h25: k_w = 64'h766a0abb3c77b2a8;
            7'h26: k_w = 64'h81c2c92e47edaee6;
            7'h27: k_w = 64'h92722c851482353b;
            7'h28: k_w = 64'ha2bfe8a14cf10364;
            7'h29: k_w = 64'ha81a664bbc423001;
            7'h2A: k_w = 64'hc24b8b70d0f89791;
            7'h2B: k_w = 64'hc76c51a30654be30;
            7'h2C: k_w = 64'hd192e819d6ef5218;
            7'h2D: k_w = 64'hd69906245565a910;
            7'h2E: k_w = 64'hf40e35855771202a;
            7'h2F: k_w = 64'h106aa07032bbd1b8;
            7'h30: k_w = 64'h19a4c116b8d2d0c8;
            7'h31: k_w = 64'h1e376c085141ab53;
            7'h32: k_w = 64'h2748774cdf8eeb99;
            7'h33: k_w = 64'h34b0bcb5e19b48a8;
            7'h34: k_w = 64'h391c0cb3c5c95a63;
            7'h35: k_w = 64'h4ed8aa4ae3418acb;
            7'h36: k_w = 64'h5b9cca4f7763e373;
            7'h37: k_w = 64'h682e6ff3d6b2b8a3;
            7'h38: k_w = 64'h748f82ee5defb2fc;
            7'h39: k_w = 64'h78a5636f43172f60;
            7'h3A: k_w = 64'h84c87814a1f0ab72;
            7'h3B: k_w = 64'h8cc702081a6439ec;
            7'h3C: k_w = 64'h90befffa23631e28;
            7'h3D: k_w = 64'ha4506cebde82bde9;
            7'h3E: k_w = 64'hbef9a3f7b2c67915;
            7'h3F: k_w = 64'hc67178f2e372532b;
            7'h40: k_w = 64'hca273eceea26619c;
            7'h41: k_w = 64'hd186b8c721c0c207;
            7'h42: k_w = 64'heada7dd6cde0eb1e;
            7'h43: k_w = 64'hf57d4f7fee6ed178;
            7'h44: k_w = 64'h06f067aa72176fba;
            7'h45: k_w = 64'h0a637dc5a2c898a6;
            7'h46: k_w = 64'h113f9804bef90dae;
            7'h47: k_w = 64'h1b710b35131c471b;
            7'h48: k_w = 64'h28db77f523047d84;
            7'h49: k_w = 64'h32caab7b40c72493;
            7'h4A: k_w = 64'h3c9ebe0a15c9bebc;
            7'h4B: k_w = 64'h431d67c49c100d4c;
            7'h4C: k_w = 64'h4cc5d4becb3e42b6;
            7'h4D: k_w = 64'h597f299cfc657e2a;
            7'h4E: k_w = 64'h5fcb6fab3ad6faec;
            7'h4F: k_w = 64'h6C44198C4A475817;
            default: k_w = 64'h0;
        endcase
    end


    //  cyclic rotation right

    function automatic [63:0] rotr;
        input [63:0] x, n;
        begin
            rotr = (x >> n) | (x << (64 - n));
        end
    endfunction

    //  4.1.3 SHA-384 and SHA-512/xxx Functions

    function automatic [63:0] ch;
        input [63:0] x, y, z;
        begin
            ch = (x & y) ^ (~x & z);
        end
    endfunction

    function automatic [63:0] maj;
        input [63:0] x, y, z;
        begin
            maj = (x & y) ^ (x & z) ^ (y & z);
        end
    endfunction

    function automatic [63:0] sum0;
        input [63:0] x;
        begin
            sum0 =  rotr(x, 28) ^ rotr(x, 34) ^ rotr(x, 39);
        end
    endfunction

    function automatic [63:0] sum1;
        input [63:0] x;
        begin
            sum1 =  rotr(x, 14) ^ rotr(x, 18) ^ rotr(x, 41);
        end
    endfunction

    function automatic [63:0] sig0;
        input [63:0] x;
        begin
            sig0 =  rotr(x,  1) ^ rotr(x,  8) ^ (x >> 7);
        end
    endfunction

    function automatic [63:0] sig1;
        input [63:0] x;
        begin
            sig1 =  rotr(x, 19) ^ rotr(x, 61) ^ (x >> 6);
        end
    endfunction

    //  message word
    wire    [63:0]  w_i     =   m_i[ 63:  0];

    //  Step 1: message schedule W_{t-i}
    wire    [63:0]  t16_w   =   m_i[ 63:  0];
    wire    [63:0]  t15_w   =   m_i[127: 64];
    wire    [63:0]  t07_w   =   m_i[639:576];
    wire    [63:0]  t02_w   =   m_i[959:896];
    wire    [63:0]  wt_w;

    assign  wt_w =  sig1(t02_w) + t07_w + sig0(t15_w) + t16_w;

    //  shift register output
    assign  m_o =   { wt_w, m_i[1023:64] };

    //  state is a packed vector
    wire    [63:0]  a_w, b_w, c_w, d_w, e_w, f_w, g_w, h_w;
    assign  { h_w, g_w, f_w, e_w, d_w, c_w, b_w, a_w } = h_i;

    //  Step 3: state iteration

    wire    [63:0]  t1_w, t2_w;
    assign  t1_w = h_w + sum1(e_w) + ch(e_w, f_w, g_w) + k_w + w_i;
    assign  t2_w = sum0(a_w) + maj(a_w, b_w, c_w);

    assign  h_o = { g_w,                //  h'
                    f_w,                //  g'
                    e_w,                //  f'
                    d_w  + t1_w,        //  e'
                    c_w,                //  d'
                    b_w,                //  c'
                    a_w,                //  b'
                    t1_w + t2_w };      //  a'

endmodule

`endif
