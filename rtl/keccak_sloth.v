//  keccak_sloth.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Simple 32-bit interface to the Keccak accelerator.

`include "config.vh"
`ifdef SLOTH_KECCAK
`include "mem_block.vh"

/*
    word    name    description

    0   KECC_MEMA   1600-bit keccak state in/out.
    50  KECC_SEED   PK.seed for intialization of F.
    58  KECC_ADRS   32-byte ADRS structure for F.
    66  KECC_SKSD   SK.seed secret key block.
    74  KECC_MTOP   End of the data register block.

    120 KECC_CTRL   Start of the control register block.
    120 KECC_TRIG   set to 0x01 to start the operation
    120 KECC_STAT   Also a status register: reads nonzero if busy
    121 KECC_STOP   Stop round (0x74) -- no need to change.
    122 KECC_SECN   Security parameter n in { 16, 24, 32 }.
    123 KECC_CHNS   Set to "s" value to start F chaining op.
                    Set to 0x40 + s for PRF + chaihing op.
                    Set to 0x80 just to perform padding for F.
*/

//  a memory mapped device with 32-bit interface

module keccak_sloth (
    input wire          clk,
    input wire          rst,
    input wire          sel,
    output reg          irq,
    input wire  [3:0]   wen,
    input wire  [6:0]   addr,
    input wire  [31:0]  wdata,
    output reg  [31:0]  rdata
);

    localparam  KECC_MEMA   =   0;
    localparam  KECC_ADRS   =   50;
    localparam  KECC_SEED   =   58;
    localparam  KECC_SKSD   =   66;
    localparam  KECC_MTOP   =   74;
    localparam  KECC_CTRL   =   120;
    localparam  KECC_TRIG   =   120;
    localparam  KECC_STOP   =   121;
    localparam  KECC_SECN   =   122;
    localparam  KECC_CHNS   =   123;

    /*
    formatting for
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

    wire                msel_w = addr < KECC_CTRL;
    wire    [6:0]       csel_w = addr;      //  register select

    reg     [31:0]      mem [0:KECC_MTOP - 1];      //  state

    reg     [7:0]       stop_r;     //  last round (8'h74)
    reg     [7:0]       rndc_r;     //  state / round constant
    reg     [7:0]       secn_r;     //  n = { 16, 24, 32 }
    reg     [7:0]       chns_r;     //  chain iteration s
    reg     [7:0]       chni_r;     //  increment
    wire    just_pad_w = chns_r[7];
    wire    wots_prf_w = chns_r[6];
    wire    [1599:0]    st_o_w;     //  keccak permutation output
    wire    [7:0]       rc_o_w;     //  next round

    //  the state register is mapped from the "memory"
    wire    [1599:0]    st_i_w = `MEM_BLOCK_50(KECC_MEMA);

    //  combinatorial keccak round
    keccak_round keccak_0 (
        .s_o(st_o_w ),                          //  state out
        .r_o(rc_o_w ),                          //  round out
        .s_i(st_i_w ),                          //  state in
        .r_i(rndc_r )                           //  round in
    );

    //  address field, adjusted by the counte
    wire    [255:0] adrs_w   = {
        mem[KECC_ADRS + 7] + {chni_r, 24'b0 },
        mem[KECC_ADRS + 6], `MEM_BLOCK_6(KECC_ADRS) };

    wire    [255:0] seed_m  = `MEM_BLOCK_8(KECC_SEED);
    wire    [255:0] hash_m  = st_i_w[255:0];
    wire    [255:0] sksd_m  = `MEM_BLOCK_8(KECC_SKSD);

    always @(posedge clk) begin

        irq     <=  0;              //  clear irq

        //  memory mapping
        if (sel && msel_w) begin        //  access to state

            rdata   <=  mem[addr];
            if (wen[0]) mem[addr][ 7: 0]    <=  wdata[ 7: 0];
            if (wen[1]) mem[addr][15: 8]    <=  wdata[15: 8];
            if (wen[2]) mem[addr][23:16]    <=  wdata[23:16];
            if (wen[3]) mem[addr][31:24]    <=  wdata[31:24];

        end else begin

            if (sel) begin

                //  control registers
                case (csel_w)

                    KECC_TRIG:  begin
                        rdata   <=  { 16'b0, chns_r, rndc_r };
                        if (wen[0]) begin
                            rndc_r  <=  wdata[ 7: 0];
                        end
                    end

                    KECC_STOP: begin
                        rdata   <=  { 24'b0, stop_r };
                        if (wen[0]) begin
                            stop_r  <=  wdata[ 7: 0];
                        end
                    end

                    KECC_SECN: begin
                        rdata   <=  { 24'b0, secn_r };
                        if (wen[0]) begin
                            secn_r  <=  wdata[ 7: 0];
                        end
                    end

                    KECC_CHNS: begin
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

                //  next state
                `MEM_BLOCK_50(KECC_MEMA) <= st_o_w;

                if (rndc_r == stop_r) begin     //  round (8'h74 = 24th)
                    rndc_r  <=  8'h00;          //  done
                    if (chns_r == 8'h00) begin
                        irq     <=  1;
                    end
                end else begin
                    rndc_r  <=  rc_o_w;         //  next rc
                end

            end else if (chns_r != 0) begin

                //  iteration
                `MEM_BLOCK_50(KECC_MEMA) <=
                    padf(secn_r, seed_m, adrs_w, wots_prf_w ? sksd_m : hash_m);

                if (just_pad_w) begin

                    //  0x80: we just stop here and use the padding (for t, h)
                    chns_r  <=  8'h00;

                end else if (wots_prf_w) begin

                    //  map WOTS_PRF to WOTS_HASH, FORS_PRF to FORS_TREE
                    mem[KECC_ADRS + 4][31:24] <=
                        (mem[KECC_ADRS + 4][31:24] == 8'h05 ? 8'h00 : 8'h03);
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
        end
    end

endmodule

`endif
