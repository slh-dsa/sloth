//  kecti3_sloth.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Masked Keccak (3-Share Threshold Implementation)

`include "config.vh"
`ifdef SLOTH_KECTI3
`include "mem_block.vh"

/*
    word    name        description

    0       KTI3_MEMA   1600-bit keccak state in/out. Share A.
    50      KTI3_MEMB   Keccak state, share B.
    100     KTI3_MEMC   Keccak state, share C.
    150                 (unused)
    152     KTI3_ADRS   32-byte ADRS structure for F.
    160     KTI3_SEED   PK.seed for intialization of F.
    168     KTI3_SKSA   SK.seed secret key block. Share A.
    176     KTI3_SKSB   Secret key, share B.
    184     KTI3_SKSC   Secret key, share C.
    192     KTI3_MTOP   End of the data register block.

    240     KTI3_CTRL   Start of the control register block.
    240     KTI3_TRIG   set to 0x01 to start the operation
    240     KTI3_STAT   Also a status register: reads nonzero if busy
    241     KTI3_STOP   Stop round (0x74) -- no need to change.
    242     KTI3_SECN   Security parameter n in { 16, 24, 32 }.
    243     KTI3_CHNS   Set to "s" value to start F chaining op.
                        Set to 0x40 + s for PRF + chaihing op.
                        Set to 0x80 just to perform padding for F.
*/

//  a memory mapped device with 32-bit interface

module kecti3_sloth (
    input wire          clk,
    input wire          rst,
    input wire          sel,
    output reg          irq,
    input wire  [3:0]   wen,
    input wire  [7:0]   addr,
    input wire  [31:0]  wdata,
    output reg  [31:0]  rdata
);

    localparam  KTI3_MEMA   =   0;
    localparam  KTI3_MEMB   =   50;
    localparam  KTI3_MEMC   =   100;
    localparam  KTI3_ADRS   =   152;
    localparam  KTI3_SEED   =   160;
    localparam  KTI3_SKSA   =   168;
    localparam  KTI3_SKSB   =   176;
    localparam  KTI3_SKSC   =   184;
    localparam  KTI3_MTOP   =   192;

    localparam  KTI3_CTRL   =   240;
    localparam  KTI3_TRIG   =   240;
    localparam  KTI3_STOP   =   241;
    localparam  KTI3_SECN   =   242;
    localparam  KTI3_CHNS   =   243;

    //  round counter
    function automatic [7:0] rc_step;
        input [7:0]  r_i;           //  rc in

        //  This matrix implements 7 steps of the LFSR described in Alg. 5;
        //  converted from Galois to Fibonacci representation and combined.
        rc_step =   ({8{r_i[0]}} & 8'h1A) ^ ({8{r_i[1]}} & 8'h34) ^
                    ({8{r_i[2]}} & 8'h68) ^ ({8{r_i[3]}} & 8'hD0) ^
                    ({8{r_i[4]}} & 8'hBA) ^ ({8{r_i[5]}} & 8'h6E) ^
                    ({8{r_i[6]}} & 8'hC6) ^ ({8{r_i[7]}} & 8'h8D);
    endfunction

    /*
    padding & formatting for:
    PRF(PK.seed, SK.seed, ADRS) = SHAKE256(PK.seed || ADRS || SK.seed, 8n)
    F(PK.seed, ADRS, M1) = SHAKE256(PK.seed || ADRS || M1 , 8n)
    */
    function automatic [1599:0] padf;
        input [7:0] n;
        input [255:0] seed, adrs, m;
        padf =  (n == 16) ? {   //  n == 16
                    512'b0, 8'h80, 560'b0, 8'h1F,
                    m[127:0], adrs, seed[127:0] } :
                (n == 24) ? {   //  n == 24
                    512'b0, 8'h80, 432'b0, 8'h1F,
                    m[191:0], adrs, seed[191:0] } :
                {   //  n == 32
                    512'b0, 8'h80, 304'b0, 8'h1F,
                    m[255:0], adrs, seed[255:0] };
    endfunction

    wire                msel_w = addr < KTI3_CTRL;
    wire    [7:0]       csel_w = addr;      //  register select

    reg     [31:0]      mem [0:KTI3_MTOP - 1];      //  state

    reg     [7:0]       stop_r;     //  last round (8'h74)
    reg     [7:0]       rndc_r;     //  state / round constant
    reg     [7:0]       secn_r;     //  n = { 16, 24, 32 }
    reg     [7:0]       chns_r;     //  chain iteration s
    reg     [7:0]       chni_r;     //  increment
    wire    just_pad_w = chns_r[7];
    wire    wots_prf_w = chns_r[6];

    //

    wire    [1599:0]    a_o_w;      //  keccak permutation output
    wire    [1599:0]    b_o_w;
    wire    [1599:0]    c_o_w;

    wire    [1599:0]    a_i_m = `MEM_BLOCK_50(KTI3_MEMA);
    wire    [1599:0]    b_i_m = `MEM_BLOCK_50(KTI3_MEMB);
    wire    [1599:0]    c_i_m = `MEM_BLOCK_50(KTI3_MEMC);

    wire    [255:0] adrs_m   = {
        mem[KTI3_ADRS + 7] + {chni_r, 24'b0 },
        mem[KTI3_ADRS + 6], `MEM_BLOCK_6(KTI3_ADRS) };

    wire    [255:0] seed_m  = `MEM_BLOCK_8(KTI3_SEED);

    wire    [255:0] hsha_m  = a_i_m[255:0];
    wire    [255:0] hshb_m  = b_i_m[255:0];
    wire    [255:0] hshc_m  = c_i_m[255:0];

    wire    [255:0] sksa_m  = `MEM_BLOCK_8(KTI3_SKSA);
    wire    [255:0] sksb_m  = `MEM_BLOCK_8(KTI3_SKSB);
    wire    [255:0] sksc_m  = `MEM_BLOCK_8(KTI3_SKSC);

    reg     [3:0]   refi_r;     //  refresh position
    wire    [7:0]   refa_w = { KTI3_SKSA[7:3], refi_r[2:0] };
    wire    [7:0]   refb_w = { KTI3_SKSB[7:3], refi_r[2:0] };
    wire    [7:0]   refc_w = { KTI3_SKSC[7:3], refi_r[2:0] };

    //  combinatorial keccak round
    kecti3_round kecti3_0 (
        .a_o(a_o_w),
        .b_o(b_o_w),
        .c_o(c_o_w),
        .a_i(a_i_m),
        .b_i(b_i_m),
        .c_i(c_i_m),
        .r_i(rndc_r)
    );

    always @(posedge clk) begin

        irq     <=  0;                      //  clear irq

        //  memory mapping
        if (sel && msel_w) begin            //  access to state

            rdata   <=  mem[addr];
            if (wen[0]) mem[addr][ 7: 0]    <=  wdata[ 7: 0];
            if (wen[1]) mem[addr][15: 8]    <=  wdata[15: 8];
            if (wen[2]) mem[addr][23:16]    <=  wdata[23:16];
            if (wen[3]) mem[addr][31:24]    <=  wdata[31:24];

        end else begin

            if (sel) begin

                //  control registers
                case (csel_w)

                    KTI3_TRIG:  begin
                        rdata   <=  { 16'b0, chns_r, rndc_r };
                        if (wen[0]) begin
                            rndc_r  <=  wdata[ 7: 0];
                        end
                    end

                    KTI3_STOP: begin
                        rdata   <=  { 24'b0, stop_r };
                        if (wen[0]) begin
                            stop_r  <=  wdata[ 7: 0];
                        end
                    end

                    KTI3_SECN: begin
                        rdata   <=  { 24'b0, secn_r };
                        if (wen[0]) begin
                            secn_r  <=  wdata[ 7: 0];
                        end
                    end

                    KTI3_CHNS: begin
                        rdata   <=  { 24'b0, chns_r };
                        if (wen[0]) begin
                            chns_r  <=  wdata[ 7: 0];
                            chni_r  <=  8'h00;
                        end
                    end

                endcase
            end

            //  round iteration (mutually exclusive from cpu state access)
            if (rndc_r != 8'h00) begin

                //  run the iteration
                `MEM_BLOCK_50(KTI3_MEMA) <= a_o_w;
                `MEM_BLOCK_50(KTI3_MEMB) <= b_o_w;
                `MEM_BLOCK_50(KTI3_MEMC) <= c_o_w;

                //  refresh the secret key meanwhile
                refi_r <= refi_r + 1;
                mem[refb_w] <=  b_o_w[31:0] ^ mem[refb_w];
                if (refi_r[3]) begin
                    mem[refc_w] <=  b_o_w[31:0] ^ mem[refc_w];
                end else begin
                    mem[refa_w] <=  b_o_w[31:0] ^ mem[refa_w];
                end

                //  round constant (8'h74 = 24th)
                if (rndc_r == stop_r) begin
                    rndc_r  <=  8'h00;      //  done
                    if (chns_r == 8'h00) begin
                        irq     <=  1;
                    end
                end else begin
                    rndc_r  <=  rc_step(rndc_r);    //  next rc
                end

            end else if (chns_r != 0) begin

                //  iteration
                `MEM_BLOCK_50(KTI3_MEMA) <=
                    padf(secn_r, seed_m, 256'b0, wots_prf_w ? sksa_m : hsha_m);
                `MEM_BLOCK_50(KTI3_MEMB) <=
                    padf(secn_r, 256'b0, adrs_m, wots_prf_w ? sksb_m : hshb_m);
                `MEM_BLOCK_50(KTI3_MEMC) <=
                    padf(secn_r, 256'b0, 256'b0, wots_prf_w ? sksc_m : hshc_m);

                if (just_pad_w) begin

                    //  0x80: we just stop here and use the padding (for t, h)
                    chns_r  <=  8'h00;

                end else if (wots_prf_w) begin

                    //  map WOTS_PRF to WOTS_HASH, FORS_PRF to FORS_TREE
                    mem[KTI3_ADRS + 4][31:24] <=
                        (mem[KTI3_ADRS + 4][31:24] == 8'h05 ? 8'h00 : 8'h03);
                    chns_r  <=  { 2'b00, chns_r[5:0] };
                    rndc_r  <=  8'h01;

                end else begin
                    chns_r  <=  chns_r - 1;
                    chni_r  <=  chni_r + 1;
                    rndc_r  <=  8'h01;
                end
            end
        end

        //  module reset

        if (rst) begin
            rndc_r  <=  8'h00;
            stop_r  <=  8'h74;
            chns_r  <=  8'h00;
            chni_r  <=  8'h00;
            secn_r  <=  8'h10;

            refi_r  <=  0;
        end
    end

endmodule

`endif
