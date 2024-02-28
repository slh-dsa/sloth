//  sha256_round.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Purely combinatorial ("stackable") logic for a SHA2-224/256 round.
//  Updates the state and the message block. No final chaining addition.

`include "config.vh"
`ifdef SLOTH_SHA256

module sha256_round(
    output wire [255:0]     h_o,        //  state out
    output wire [511:0]     m_o,        //  message out
    input wire  [255:0]     h_i,        //  state in
    input wire  [511:0]     m_i,        //  message in
    input wire  [5:0]       t_i         //  round 0..63
);
    //  round constants
    reg [31:0] k_w;

    always@(t_i) begin
        case(t_i)
            6'h00: k_w = 32'h428A2F98;
            6'h01: k_w = 32'h71374491;
            6'h02: k_w = 32'hB5C0FBCF;
            6'h03: k_w = 32'hE9B5DBA5;
            6'h04: k_w = 32'h3956C25B;
            6'h05: k_w = 32'h59F111F1;
            6'h06: k_w = 32'h923F82A4;
            6'h07: k_w = 32'hAB1C5ED5;
            6'h08: k_w = 32'hD807AA98;
            6'h09: k_w = 32'h12835B01;
            6'h0A: k_w = 32'h243185BE;
            6'h0B: k_w = 32'h550C7DC3;
            6'h0C: k_w = 32'h72BE5D74;
            6'h0D: k_w = 32'h80DEB1FE;
            6'h0E: k_w = 32'h9BDC06A7;
            6'h0F: k_w = 32'hC19BF174;
            6'h10: k_w = 32'hE49B69C1;
            6'h11: k_w = 32'hEFBE4786;
            6'h12: k_w = 32'h0FC19DC6;
            6'h13: k_w = 32'h240CA1CC;
            6'h14: k_w = 32'h2DE92C6F;
            6'h15: k_w = 32'h4A7484AA;
            6'h16: k_w = 32'h5CB0A9DC;
            6'h17: k_w = 32'h76F988DA;
            6'h18: k_w = 32'h983E5152;
            6'h19: k_w = 32'hA831C66D;
            6'h1A: k_w = 32'hB00327C8;
            6'h1B: k_w = 32'hBF597FC7;
            6'h1C: k_w = 32'hC6E00BF3;
            6'h1D: k_w = 32'hD5A79147;
            6'h1E: k_w = 32'h06CA6351;
            6'h1F: k_w = 32'h14292967;
            6'h20: k_w = 32'h27B70A85;
            6'h21: k_w = 32'h2E1B2138;
            6'h22: k_w = 32'h4D2C6DFC;
            6'h23: k_w = 32'h53380D13;
            6'h24: k_w = 32'h650A7354;
            6'h25: k_w = 32'h766A0ABB;
            6'h26: k_w = 32'h81C2C92E;
            6'h27: k_w = 32'h92722C85;
            6'h28: k_w = 32'hA2BFE8A1;
            6'h29: k_w = 32'hA81A664B;
            6'h2A: k_w = 32'hC24B8B70;
            6'h2B: k_w = 32'hC76C51A3;
            6'h2C: k_w = 32'hD192E819;
            6'h2D: k_w = 32'hD6990624;
            6'h2E: k_w = 32'hF40E3585;
            6'h2F: k_w = 32'h106AA070;
            6'h30: k_w = 32'h19A4C116;
            6'h31: k_w = 32'h1E376C08;
            6'h32: k_w = 32'h2748774C;
            6'h33: k_w = 32'h34B0BCB5;
            6'h34: k_w = 32'h391C0CB3;
            6'h35: k_w = 32'h4ED8AA4A;
            6'h36: k_w = 32'h5B9CCA4F;
            6'h37: k_w = 32'h682E6FF3;
            6'h38: k_w = 32'h748F82EE;
            6'h39: k_w = 32'h78A5636F;
            6'h3A: k_w = 32'h84C87814;
            6'h3B: k_w = 32'h8CC70208;
            6'h3C: k_w = 32'h90BEFFFA;
            6'h3D: k_w = 32'hA4506CEB;
            6'h3E: k_w = 32'hBEF9A3F7;
            6'h3F: k_w = 32'hC67178F2;
        endcase
    end

    //  cyclic rotation right

    function automatic [31:0] rotr;
        input [31:0] x, n;
        begin
            rotr = (x >> n) | (x << (32 - n));
        end
    endfunction

    //  4.1.2 SHA-224 and SHA-256 Functions

    function automatic [31:0] ch;
        input [31:0] x, y, z;
        begin
            ch = (x & y) ^ (~x & z);
        end
    endfunction

    function automatic [31:0] maj;
        input [31:0] x, y, z;
        begin
            maj = (x & y) ^ (x & z) ^ (y & z);
        end
    endfunction

    function automatic [31:0] sum0;
        input [31:0] x;
        begin
            sum0 =  rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
        end
    endfunction

    function automatic [31:0] sum1;
        input [31:0] x;
        begin
            sum1 =  rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
        end
    endfunction

    function automatic [31:0] sig0;
        input [31:0] x;
        begin
            sig0 =  rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
        end
    endfunction

    function automatic [31:0] sig1;
        input [31:0] x;
        begin
            sig1 =  rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
        end
    endfunction

    //  message word
    wire    [31:0]  w_i     =   m_i[ 31:  0];

    //  Step 1: message schedule W_{t-i}
    wire    [31:0]  t16_w   =   m_i[ 31:  0];
    wire    [31:0]  t15_w   =   m_i[ 63: 32];
    wire    [31:0]  t07_w   =   m_i[319:288];
    wire    [31:0]  t02_w   =   m_i[479:448];
    wire    [31:0]  wt_w;

    assign  wt_w =  sig1(t02_w) + t07_w + sig0(t15_w) + t16_w;

    //      shift register output
    assign  m_o =   { wt_w, m_i[511:32] };

    //  state is a packed vector
    wire    [31:0]  a_w, b_w, c_w, d_w, e_w, f_w, g_w, h_w;
    assign  { h_w, g_w, f_w, e_w, d_w, c_w, b_w, a_w } = h_i;

    //  Step 3: state iteration

    wire    [31:0]  t1_w, t2_w;
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
