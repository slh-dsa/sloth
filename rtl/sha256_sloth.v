//  sha256_sloth.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Simple 32-bit interface to the SHA2-256 accelerator.

`include "config.vh"
`ifdef SLOTH_SHA256
`include "mem_block.vh"

/*
    word    name    description

    0       S256_HASH   Hash chaining value / output.
    8       S256_MSGB   Message block for hash input.
    24      S256_MEND   End of message block.
    24      S256_SEED   PK.seed for intialization of F.
    32      S256_ADRS   32-byte ADRS structure for F.
    40      S256_SKSD   SK.seed secret key for PRF.
    48      S256_MTOP   End of the data register block.
    64      S256_MSH2   Message block shifted by 2 bytes.
    120     S256_CTRL   Start of the control register block.
    120     S256_TRIG   set to 0x01 to start Keccak,
                        0x02 to start chain iteration,
                        0x03 for PRF + Chain.
    120     S256_STAT   Also a status register: reads nonzero if busy
    122     S256_SECN   Security parameter n in { 16, 24, 32 }.
    123     S256_CHNS   Set to "s" value to start F chaining op.
                        Set to 0x80 just to perform padding for F.
*/

//  a memory mapped device with 32-bit interface

module sha256_sloth (
    input wire          clk,
    input wire          rst,
    input wire          sel,
    output reg          irq,
    input wire  [3:0]   wen,
    input wire  [6:0]   addr,
    input wire  [31:0]  wdata,
    output reg  [31:0]  rdata
);

    localparam  S256_HASH   =   0;
    localparam  S256_MSGB   =   8;
    localparam  S256_MEND   =   24;
    localparam  S256_SEED   =   24;
    localparam  S256_ADRS   =   32;
    localparam  S256_SKSD   =   40;
    localparam  S256_MTOP   =   48;
    localparam  S256_MSH2   =   64;
    localparam  S256_CTRL   =   120;
    localparam  S256_TRIG   =   120;
    localparam  S256_STAT   =   120;
    localparam  S256_SECN   =   122;
    localparam  S256_CHNS   =   123;

    wire                msel_w = addr < S256_CTRL;
    wire    [6:0]       csel_w = addr;          //  register select
    wire    [5:0]       addr_w = addr[5:0];     //  memory address
    wire                msh2_w = addr[6];       //  MSH2
    wire    [5:0]       adr0_w = addr_w;
    wire    [5:0]       adr1_w = addr_w + 1;

    reg     [31:0]      mem [0:S256_MTOP - 1];  //  memory mapped
    reg     [7:0]       t_r;                    //  state / round #
    reg     [7:0]       secn_r;                 //  n = { 16, 24, 32 }
    reg     [7:0]       chns_r;                 //  chain iteration s
    reg     [7:0]       chni_r;                 //  increment

    wire    [255:0]     hash_m  = `MEM_BLOCK_8(S256_HASH);  //  hash
    wire    [511:0]     msgb_m  = `MEM_BLOCK_16(S256_MSGB); //  message
    wire    [255:0]     seed_m  = `MEM_BLOCK_8(S256_SEED);  //  PK.seed
    wire    [255:0]     sksd_m  = `MEM_BLOCK_8(S256_SKSD);  //  SK.seed

    //  ADRSc = ADRS[3] || ADRS[8:16] || ADRS[19] || ADRS[20:32]).
    //  this looks even weirder because of the endianess conversion.
    //  Note: register offset S256_ADRS = 32 is fixed here.
    wire    [175:0]     adrsc_w = {
        mem[39][15: 8], mem[39][ 7: 0] + chni_r,    //  chain index
        mem[38][15: 8], mem[38][ 7: 0], mem[39][31:24], mem[39][23:16],
        mem[37][15: 8], mem[37][ 7: 0], mem[38][31:24], mem[38][23:16],
        mem[35][ 7: 0], mem[36][ 7: 0], mem[37][31:24], mem[37][23:16],
        mem[34][ 7: 0], mem[35][31:24], mem[35][23:16], mem[35][15: 8],
        mem[32][ 7: 0], mem[34][31:24], mem[34][23:16], mem[34][15: 8]
    };

    /*
    formatting for 2nd block with contents: (ADRSc || x)
    F(PK.seed, ADRS, M1)        = Trunc_n(SHA-256(PK.seed ||
                                    toByte(0, 64 − n) || ADRSc || M1 ))
    PRF(PK.seed, SK.seed, ADRS) = Trunc_n(SHA-256(PK.seed ||
                                    toByte(0, 64 − n) || ADRSc || SK.seed))
    */

    function automatic [511:0] padf;
        input [7:0] n;
        input [175:0] ac;
        input [255:0] x;

        padf = { 16'h00000, 8'h03,  //  length padding: 102, 110, or 118 bytes
            (n == 16 ? 8'h30 : n == 24 ? 8'h70 : 8'hB0 ),
            32'b0,
            (n == 32 ? { x[239:224], 1'b1 } : 17'b0), 15'b0,
            (n == 32 ? { x[207:192], x[255:240] } : 32'b0),
            (n == 16 ? 16'b0 : x[175:160]),
                (n == 32 ? x[223:208] : { n == 24, 15'b0 }),
            (n == 16 ? 32'b0 : { x[143:128], x[191:176] }),
            x[111:  96],    (n == 16 ? { 1'b1, 15'b0 } : x[159:144]),
            x[ 79:  64],    x[127:112],
            x[ 47:  32],    x[ 95: 80],
            x[ 15:   0],    x[ 63: 48],
            ac[175:160],    x[ 31: 16],
            ac[159:  0] };
    endfunction

    wire    [255:0]     h_o_w;              //  hash state out
    wire    [511:0]     m_o_w;              //  message sched out
    reg     [255:0]     h_s_r;              //  hash state in
    reg     [511:0]     m_s_r;              //  message sched in

    //  combinatorial sha2-256 round

    sha256_round sha256_0 (
        .h_o(h_o_w      ),                  //  state out
        .m_o(m_o_w      ),                  //  message sched out
        .h_i(h_s_r      ),                  //  state in
        .m_i(m_s_r      ),                  //  message sched out
        .t_i(t_r[5:0]   )                   //  round index
    );

    always @(posedge clk) begin

        irq     <=  0;                      //  clear irq

        //  memory mapping
        if (sel && msel_w) begin                //  access to state

            if (!msh2_w) begin

                //  Internal SHA2 logic is big-endian
                rdata   <=  { mem[addr_w][ 7: 0], mem[addr_w][15: 8],
                              mem[addr_w][23:16], mem[addr_w][31:24] };

                if (wen[0]) mem[addr_w][31:24]  <=  wdata[ 7: 0];
                if (wen[1]) mem[addr_w][23:16]  <=  wdata[15: 8];
                if (wen[2]) mem[addr_w][15: 8]  <=  wdata[23:16];
                if (wen[3]) mem[addr_w][ 7: 0]  <=  wdata[31:24];

            end else begin

                //  we're writing to address +2 (into 2 words)
                //  note that adr0_w andr1_w are masked to 6 bits
                rdata   <=   32'h0000_0000;
                if (adr0_w >= S256_MSGB && adr0_w < S256_MEND) begin
                    if (wen[0]) mem[adr0_w][15: 8]  <=  wdata[ 7: 0];
                    if (wen[1]) mem[adr0_w][ 7: 0]  <=  wdata[15: 8];
                end
                if (adr1_w >= S256_MSGB && adr1_w < S256_MEND) begin
                    if (wen[2]) mem[adr1_w][31:24]  <=  wdata[23:16];
                    if (wen[3]) mem[adr1_w][23:16]  <=  wdata[31:24];
                end
            end

        end else begin                  //  control registers

            if (sel) begin

                case (csel_w)

                    S256_TRIG:  begin
                        rdata   <=  { 24'b0, t_r };
                        if (wen[0]) begin
                            t_r <=  wdata[ 7: 0];
                        end
                    end

                    S256_SECN: begin
                        rdata   <=  { 24'b0, secn_r };
                        if (wen[0]) begin
                            secn_r  <=  wdata[ 7: 0];
                        end
                    end

                    S256_CHNS: begin
                        rdata   <=  { 24'b0, chns_r };
                        if (wen[0]) begin
                            chns_r  <=  wdata[ 7: 0];
                            chni_r  <=  8'h00;
                        end
                    end

                endcase
            end


            if (t_r[7] == 1'b0) begin

                case (t_r)

                    //  Raw op 0x01
                    8'h01: begin
                        h_s_r   <=  hash_m;
                        m_s_r   <=  msgb_m;
                        t_r     <=  8'h80;  //  skip to 0x80 to run it
                    end

                    //  Chaining (padding)
                    8'h02: begin
                        `MEM_BLOCK_8(S256_HASH)  <= seed_m;
                        `MEM_BLOCK_16(S256_MSGB) <=
                            padf(secn_r, adrsc_w, hash_m);

                        if (chns_r == 0) begin
                            //  just perform padding if s=0
                            t_r     <=  8'h00;
                        end else begin
                            //  next iteration
                            chns_r  <=  chns_r - 1;
                            chni_r  <=  chni_r + 1;
                            t_r     <=  8'h01;
                        end
                    end

                    //  PRF + Chain
                    8'h03: begin
                        `MEM_BLOCK_8(S256_HASH)  <= seed_m;
                        `MEM_BLOCK_16(S256_MSGB) <=
                            padf(secn_r, adrsc_w, sksd_m);

                        //  map WOTS_PRF to WOTS_HASH, FORS_PRF to FORS_TREE
                        mem[S256_ADRS + 4][ 7: 0] <=
                        (mem[S256_ADRS + 4][ 7: 0] == 8'h05 ? 8'h00 : 8'h03);

                        t_r <=  8'h01;              //  start
                    end

                    default: begin
                    end

                endcase

            end else if (t_r < 8'hC0) begin

                //  "running state"
                h_s_r   <=  h_o_w;
                m_s_r   <=  m_o_w;
                t_r     <=  t_r + 1;

            end else begin

                //  final addition
                mem[0] <= mem[0] + h_s_r[ 31:  0];
                mem[1] <= mem[1] + h_s_r[ 63: 32];
                mem[2] <= mem[2] + h_s_r[ 95: 64];
                mem[3] <= mem[3] + h_s_r[127: 96];
                mem[4] <= mem[4] + h_s_r[159:128];
                mem[5] <= mem[5] + h_s_r[191:160];
                mem[6] <= mem[6] + h_s_r[223:192];
                mem[7] <= mem[7] + h_s_r[255:224];

                if (chns_r == 0) begin
                    t_r     <=  8'h00;
                    irq     <=  1;
                end else begin
                    t_r     <=  8'h02;
                end
            end
        end

        //  system reset (stop)
        if (rst) begin
            t_r     <=  8'h00;
            chns_r  <=  8'h00;
            chni_r  <=  8'h00;
            secn_r  <=  8'h10;
        end
    end


endmodule

`endif
