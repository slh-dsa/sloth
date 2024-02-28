//  sha512_sloth.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Simple 32-bit interface to the SHA2-512 accelerator.

`include "config.vh"
`ifdef SLOTH_SHA512
`include "mem_block.vh"

/*
    word    name    description

    0   S512_HASH   Hash chaining value / output.
    16  S512_MSGB   Message block for hash input.
    48  S512_MEND   End of message block.
    48  S512_MTOP   End of the data register block.
    64  S512_MSH2   Message block shifted by 2 bytes.

    120 S512_CTRL   Start of the control register block.
    120 S512_TRIG   set to 0x01 to start the operation
    120 S512_STAT   Also a status register: reads nonzero if busy
*/

//  a memory mapped device with 32-bit interface

module sha512_sloth (
    input wire          clk,
    input wire          rst,
    input wire          sel,
    output reg          irq,
    input wire  [3:0]   wen,
    input wire  [6:0]   addr,
    input wire  [31:0]  wdata,
    output reg  [31:0]  rdata
);
    localparam  S512_HASH   =   0;
    localparam  S512_MSGB   =   16;
    localparam  S512_MEND   =   48;
    localparam  S512_MTOP   =   48;
    localparam  S512_MSH2   =   64;
    localparam  S512_CTRL   =   120;
    localparam  S512_TRIG   =   120;
    localparam  S512_STAT   =   120;

    wire                msel_w = addr < S512_CTRL;
    wire    [6:0]       csel_w = addr;              //  register select
    wire    [5:0]       addr_w = addr[5:0] ^ 1;     //  endianess flip
    wire                msh2_w = addr[6];           //  MSH2
    wire    [5:0]       adr0_w = addr[5:0] ^ 1;
    wire    [5:0]       adr1_w = (addr[5:0] + 1) ^ 1;

    reg     [31:0]      mem [0:S512_MTOP - 1];      //  memory mapped
    reg     [7:0]       t_r;                        //  state / round #

    wire    [511:0]     hash_m = `MEM_BLOCK_16(S512_HASH);
    wire    [1023:0]    msgb_m = `MEM_BLOCK_32(S512_MSGB);

    wire    [511:0]     h_o_w;              //  hash state out
    wire    [1023:0]    m_o_w;              //  message sched out
    reg     [511:0]     h_s_r;              //  hash state in
    reg     [1023:0]    m_s_r;              //  message sched in

    //  combinatorial sha2-512 round
    sha512_round sha512_0 (
        .h_o(h_o_w      ),                  //  state out
        .m_o(m_o_w      ),                  //  message sched out
        .h_i(h_s_r      ),                  //  state in
        .m_i(m_s_r      ),                  //  message sched out
        .t_i(t_r[6:0]   )                   //  round index
    );

    always @(posedge clk) begin

        irq     <=  0;                      //  clear irq

        //  memory mapping
        if (sel) begin

            if (msel_w) begin                   //  access to state

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
                    if (adr0_w >= S512_MSGB && adr0_w < S512_MEND) begin
                        if (wen[0]) mem[adr0_w][15: 8]  <=  wdata[ 7: 0];
                        if (wen[1]) mem[adr0_w][ 7: 0]  <=  wdata[15: 8];
                    end
                    if (adr1_w >= S512_MSGB && adr1_w < S512_MEND) begin
                        if (wen[2]) mem[adr1_w][31:24]  <=  wdata[23:16];
                        if (wen[3]) mem[adr1_w][23:16]  <=  wdata[31:24];
                    end
                end

            end else begin                  //  control registers

                case (csel_w)

                    S512_TRIG:  begin
                        rdata   <=  { 24'b0, t_r };
                        if (wen[0]) begin
                            t_r <=  wdata[ 7: 0];
                        end
                    end

                endcase
            end

        end

        if (t_r[7] == 1'b0) begin

            //  start the operation 0x01
            if (t_r[0]) begin
                h_s_r   <=  hash_m;
                m_s_r   <=  msgb_m;
                t_r     <=  8'h80;
            end

        end else if (t_r[6:0] < 80) begin

            //  "running state"
            h_s_r   <=  h_o_w;
            m_s_r   <=  m_o_w;
            t_r     <=  t_r + 1;

        end else begin

            //  final addition
            { mem[ 1], mem[ 0] } <= { mem[ 1], mem[ 0] } + h_s_r[ 63:  0];
            { mem[ 3], mem[ 2] } <= { mem[ 3], mem[ 2] } + h_s_r[127: 64];
            { mem[ 5], mem[ 4] } <= { mem[ 5], mem[ 4] } + h_s_r[191:128];
            { mem[ 7], mem[ 6] } <= { mem[ 7], mem[ 6] } + h_s_r[255:192];
            { mem[ 9], mem[ 8] } <= { mem[ 9], mem[ 8] } + h_s_r[319:256];
            { mem[11], mem[10] } <= { mem[11], mem[10] } + h_s_r[383:320];
            { mem[13], mem[12] } <= { mem[13], mem[12] } + h_s_r[447:384];
            { mem[15], mem[14] } <= { mem[15], mem[14] } + h_s_r[511:448];

            t_r     <=  8'h00;
            irq     <=  1;
        end

        //  system reset (stop)
        if (rst) begin
            t_r     <=  8'h00;
        end
    end

endmodule

`endif
