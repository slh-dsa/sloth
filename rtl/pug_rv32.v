//  pug_rv32.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === A small RV32 core. Modified harvard Architecture version.
//      ( Used for Codesign / IUT -- not for production. )

`include "config.vh"

//  comment out if you don't want this
`ifdef VERILATOR
`define CORE_PC_LOG
`endif

//`define CORE_DEBUG

module pug_rv32 #(
    parameter           XLEN        = 32,
    parameter   [31:0]  RESET_PC    = 32'h0000_0000,
    parameter   [31:0]  RESET_SP    = 32'h0000_0000
) (
    input wire          clk,                //  clock
    input wire          rst,                //  reset = 1
    output reg          trap        = 0,    //  trap ?
    input wire          irq,                //  generic interrupt

    output wire         mem0_valid,         //  data memory (rw)
    input wire          mem0_ready,
    output reg  [31:0]  mem0_addr   = 0,
    output reg  [31:0]  mem0_wdata  = 0,
    output reg  [ 3:0]  mem0_wstrb  = 0,
    input wire  [31:0]  mem0_rdata,

    output wire         mem1_valid,         //  program memory (ro)
    input wire          mem1_ready,
    output wire [31:0]  mem1_addr,
    input wire  [31:0]  mem1_rdata
);
`ifdef CORE_PC_LOG
    integer logf;
    reg     [31:0]  log_clk;
    initial begin
        log_clk =   0;
        logf = $fopen("core_pc.log");
    end
`endif
    localparam          BAD_ADDR    = 32'hFFFF_FFFF;
    localparam          RV32_NOP    = 32'h0000_0013;

    //  diagnostics
`ifdef  CORE_DEBUG
    reg  [31:0] clk_cnt = 0, step_cnt = 0;
`endif

    //  interrupts
    reg         irq_fl  = 0;                //  unhandled interrupt
    reg         wfi     = 0;                //  cpu is waiting for interrupt

    //  interrupt lines (to wake up WFI)
    wire    irq_w =
`ifdef CORE_CUSTOM0
        c0_irq_w    ||                      //  Custom-0 IRQ
`endif
        irq;                                //  External IRQ

`ifndef CORE_E16REG
    reg [4:0]   rst_cnt = 31;               //  reset sequence counter
`else
    reg [3:0]   rst_cnt = 15;
`endif
    wire        running = !rst && (rst_cnt == 0) && !trap && !wfi;

    //  load/store state
    reg         load    = 0, load1;         //  load requested (prev)
    reg  [1:0]  ladr;                       //  load address low bits
    reg  [2:0]  lfn3;                       //  load function ("funct3")
    reg         store   = 0, store1;        //  store requrested (prev)
    reg  [3:0]  wstrb1  = 4'b0000;

    assign      mem0_valid  =   (load || store);

    //  memory load logic; address-shifted input value
    wire [31:0] rd_sh   =   ladr[1:0] == 2'b01 ? {  8'b0, mem0_rdata[31: 8] } :
                            ladr[1:0] == 2'b10 ? { 16'b0, mem0_rdata[31:16] } :
                            ladr[1:0] == 2'b11 ? { 24'b0, mem0_rdata[31:24] } :
                            mem0_rdata[31: 0];

    //  load instruction
    wire [31:0] rd_l    =   lfn3[1] ? mem0_rdata[31: 0] :   (lfn3[0] ?
                                {{16{rd_sh[15] && !lfn3[2]}}, rd_sh[15:0]} :
                                {{24{rd_sh[7] && !lfn3[2]}}, rd_sh[7:0]});

    //  program flow
    reg  [31:0] pc      =   RESET_PC;       //  current program counter
    reg  [31:0] pc_get  =   RESET_PC;       //  instruction word to get
    wire [31:0] pc_adr0 =   { pc_get[31:2], 2'b00 };
    assign  mem1_addr   =   pc_adr0;        //  hardware fetch
    assign  mem1_valid  =   1;

    reg  [31:0] pc_adr1 =   BAD_ADDR;       //  instruction cache
    wire [31:0] pc_dat1 =   mem1_rdata;
    reg  [31:0] pc_adr2 =   BAD_ADDR;
    reg  [31:0] pc_dat2 =   RV32_NOP;
    reg  [31:0] pc_adr3 =   BAD_ADDR;
    reg  [31:0] pc_dat3 =   RV32_NOP;

    reg         flush_i =   0;              //  flush instruction cache

    //  decoder (uncompress stage)
    reg  [31:0] dec_pc  =   RESET_PC;       //  next instruction to decode

    reg  [31:0] ins     =   RV32_NOP;       //  current executing instruction
`ifdef CORE_COMPRESSED
    reg         ins_c   =   0;              //  was compressed ?
`endif
    reg  [31:0] ins_pc  =   BAD_ADDR;       //  address of instruction
    wire        ins_ok  =   running && pc == ins_pc;

    //  next instruction (assuming no branch)
`ifdef CORE_COMPRESSED
    wire [31:0] pc1_w   =   pc + (ins_c ? 2 : 4);
`else
    wire [31:0] pc1_w   =   pc + 4;         //  points to next instr
`endif

`ifdef CORE_COMPRESSED

    //  instruction cache

    wire [31:0] pc_de2  =   dec_pc + 2;     //  high half-word address

    wire        pc_lo1  =   dec_pc[31:2] == pc_adr1[31:2];  //  lo in 1
    wire        pc_hi1  =   pc_de2[31:2] == pc_adr1[31:2];  //  hi in 1

    wire        pc_lo2  =   dec_pc[31:2] == pc_adr2[31:2];  //  lo in 2
    wire        pc_hi2  =   pc_de2[31:2] == pc_adr2[31:2];  //  hi in 2

    wire        pc_lo3  =   dec_pc[31:2] == pc_adr3[31:2];  //  lo in 3
    wire        pc_hi3  =   pc_de2[31:2] == pc_adr3[31:2];  //  hi in 3

    wire        pc_lo   =   pc_lo1 || pc_lo2 || pc_lo3;     //  have it?
    wire        pc_hi   =   pc_hi1 || pc_hi2 || pc_hi3;

    //  low 16 bits
    wire [15:0] ins_lo  =   pc_lo1 ?        ( dec_pc[1] ?
                                pc_dat1[31:16] : pc_dat1[15:0] ) :
                            pc_lo2 ?        ( dec_pc[1] ?
                                pc_dat2[31:16] : pc_dat2[15:0] ) :
                            /* pc_lo3 ? */  ( dec_pc[1] ?
                                pc_dat3[31:16] : pc_dat3[15:0] );

    //  high 16 bits (pc_de2[1] == !dec_pc[1])
    wire [15:0] ins_hi  =   pc_hi1 ?        ( dec_pc[1] ?
                                pc_dat1[15:0] : pc_dat1[31:16] ) :
                            pc_hi2 ?        ( dec_pc[1] ?
                                pc_dat2[15:0] : pc_dat2[31:16] ) :
                            /* pc_hi3 ? */  ( dec_pc[1] ?
                                pc_dat3[15:0] : pc_dat3[31:16] );


    //  is the instruction compressed ?
    wire        dec_c   =   ins_lo[1:0] != 2'b11;

    wire [31:0] ins_unc;                    //  uncompressed instruction
    pug_rvc rv32c(ins_lo, ins_unc);         //  rvc decode/uncompress logic

    //  do we have an instruction ?
    wire        ins_hav =   dec_c ? pc_lo : pc_lo && pc_hi;

    //  decoded (uncompressed and assembled) instruction
    wire [31:0] dec_ins =   dec_c ? ins_unc : { ins_hi, ins_lo };

`else

    //  no compression
    wire        pc_in1  =   dec_pc[31:2] == pc_adr1[31:2];
    wire        pc_in2  =   dec_pc[31:2] == pc_adr2[31:2];
    wire        pc_in3  =   dec_pc[31:2] == pc_adr3[31:2];
    wire        ins_hav =   pc_in1 || pc_in2 || pc_in3;
    wire [31:0] dec_ins =   pc_in1 ? pc_dat1 :
                                pc_in2 ? pc_dat2 : pc_dat3;
`endif

    //  register file

`ifndef CORE_E16REG
    reg  [31:0] rx [0:31];                  //  register file
`else
    reg  [31:0] rx [0:15];                  //  "e" - reduced set
`endif

    reg  [4:0]  rdr;                        //  result register index
    reg  [31:0] rdx;                        //  result register value
    reg         rdw;                        //  flag: write rdx to x[rdr]

    //  instruction decoding wires
    wire [6:0]  dc_op   =   ins[ 6: 0];     //  major opcode
    wire [4:0]  dc_rd   =   ins[11: 7];     //  destination register
    wire [2:0]  dc_fn3  =   ins[14:12];     //  "funct3" minor opcode
    wire [4:0]  dc_rs1  =   ins[19:15];     //  source register 1
    wire [4:0]  dc_rs2  =   ins[24:20];     //  source register 2
    wire [6:0]  dc_fn7  =   ins[31:25];     //  "funct7" minor opcode

    //  all immediates are sign-extended
    wire [31:0] dc_ii   =   { {20{ins[31]}}, ins[31:20] };
    wire [31:0] dc_is   =   { {20{ins[31]}}, ins[31:25], ins[11: 7] };
    wire [31:0] dc_ib   =   { {20{ins[31]}}, ins[7], ins[30:25],
                                ins[11: 8], 1'b0 };
    wire [31:0] dc_iu   =   { ins[31:12], 12'b0 };
    wire [31:0] dc_ij   =   { {12{ins[31]}}, ins[19:12], ins[20],
                                ins[30:21], 1'b0} ;

    //  current RS1 and RS2 source register values
    wire [31:0] rs1_w   =   dc_rs1 == 5'b0 ? 32'b0 :
                            rdw && dc_rs1 == rdr ? rdx :
                            rx[dc_rs1];
    wire [31:0] rs2_w   =   dc_rs2 == 5'b0 ? 32'b0 :
                            rdw && dc_rs2 == rdr ? rdx :
                            rx[dc_rs2];


    //  comparisons
    wire        cr_ltu  =   rs1_w < rs2_w;  //  less than (u)
    wire        cr_lts  =   (rs1_w[31] == 1 && rs2_w[31] == 0) ||
                            ((rs1_w[31] == rs2_w[31]) && cr_ltu);

    wire        ci_ltu  =   rs1_w < dc_ii;  //  cmp immediate
    wire        ci_lts  =   (rs1_w[31] == 1 && dc_ii[31] == 0) ||
                            ((rs1_w[31] == dc_ii[31]) && ci_ltu);

    //  branch condition
    wire        branch  =   dc_fn3[0] ^ (dc_fn3[2:1] == 2'b00 &&    //  not?
                                    (rs1_w == rs2_w) ||             //  EQ/NE
                                dc_fn3[2:1] == 2'b10 && cr_lts ||   //  LT/GE
                                dc_fn3[2:1] == 2'b11 && cr_ltu);    //  LTU/GEU

    //  pointer arithmetic
    wire [31:0] ladr_w  =   dc_ii + rs1_w;          //  load address
    wire [31:0] sadr_w  =   dc_is + rs1_w;          //  store address
    wire [31:0] jalr_w  =   (dc_ii + rs1_w) & ~1;   //  jalr address

    //  jal / branch address
    wire [31:0] jalbr_w =   pc + (ins[3] ? dc_ij : dc_ib);

    //  for multi-cycle instructions
    reg [31:0]  rs1_r;
    reg [31:0]  rs2_r;
    reg [31:0]  ins_r = 0;

    //  RV32M multiplication/division extension
`ifdef CORE_MULDIV
    wire [31:0] m_rd;                       //  result from muldiv
    wire        m_done;                     //  1=: result available
    reg         m_rst   = 0;                //  poll the result
    reg [2:0]   m_fn3   = 0;                //  function selector
    reg         m_run   = 0;                //  running
    reg         m_go    = 0;                //  start pulse
    pug_muldiv rv32_m0 (
        .clk    (clk),                      //  clock input
        .go     (m_go),                     //  multdiv instruction selected
        .rst    (m_rst),                    //  up for 1 cycle; result polled
        .done   (m_done),                   //  done (meaningless unless sel)
        .rd     (m_rd),                     //  result (out)
        .rs1    (rs1_r),                    //  decoded, fetched rs1
        .rs2    (rs2_r),                    //  decoded, fetched rs2
        .fn3    (ins_r[14:12])              //  for sub-instruction decode
    );
`endif

    //  Combinatorial AES and SM4 extension

`ifdef CORE_KRYPTO
    wire [31:0] aes_rd_w;

    rvk_aes32 aes0 (
        .rd     (aes_rd_w),                 //  same-cycle output
        .rs1    (rs1_w),                    //  decoded, fetched rs1
        .rs2    (rs2_w),                    //  decoded, fetched rs2
        .ins    (ins)
    );
`endif

    //  main execution unit

    always @(posedge clk) begin

`ifdef CORE_PC_LOG
        log_clk     <=  log_clk + 1;
`endif
        rdw         <=  0;                  //  default: don't set register

        //  store cycle

        store1  <=  store;                  //  store cycle
        wstrb1  <=  mem0_wstrb;
        if (store && mem0_ready) begin      //  give SoC 1 cycle to respond
            mem0_wstrb  <=  4'b0000;
            store       <=  0;
        end else if (store1 && !mem0_ready) begin
            mem0_wstrb  <=  wstrb1;         //  try again
            store       <=  1;
        end

        //  handle interrupts

        if (irq_w) begin
            if (wfi) begin
                wfi     <= 0;               //  no longer waiting
                irq_fl  <= 0;
            end else begin
                irq_fl  <= 1;               //  pending irq set
            end
        end

        //  handle reset

        if (rst) begin
            mem0_wstrb  <=  4'b0000;        //  no write
            pc          <=  RESET_PC;       //  reset pc
            ins         <=  RV32_NOP;       //  nop
            ins_r       <=  RV32_NOP;
            load        <=  0;              //  no load
            store       <=  0;
            trap        <=  0;              //  no trap
            wfi         <=  0;              //  no wfi
`ifndef CORE_E16REG
            rst_cnt     <=  31;             //  start reset cycle
`else
            rst_cnt     <=  15;             //  start reset cycle
`endif
            pc_get      <=  RESET_PC;
            flush_i     <=  1;              //  flush instruction cache
`ifdef CORE_MULDIV
            m_rst       <=  1;              //  poll resets the muldiv unit
            m_run       <=  0;
            m_go        <=  0;
`endif
        end else begin

`ifdef CORE_MULDIV
            m_rst       <=  0;                  //  muldiv poll
            m_go        <=  0;                  //  start signal
`endif
            //  clear registers during reset cycle
            if (|rst_cnt) begin
                rdr         <=  rst_cnt;
                rdx         <=  rst_cnt == 2 ? RESET_SP : 32'h0000_0000;
                rdw         <=  1;
                rst_cnt     <=  rst_cnt - 1'b1;
            end
`ifdef CORE_DEBUG
            else begin
                clk_cnt     <=  clk_cnt + 1;
            end
`endif
        end

`ifdef CORE_DEBUG
        if (!running) begin
            $display("[RESET] (%2d)\trst=%d trap=%d",
                rst_cnt, rst, trap);
        end
            else begin

            $display("\n[CLK] (%6d)\tready0=%d  ready1=%d   rdata1=%08h  ins=%08h",
                clk_cnt, mem0_ready, mem1_ready, mem1_rdata, ins);
            $display("\t\tpc=%08h ins_pc=%08h  pc_get=%08h",
                pc, ins_pc, pc_get);
            $display("\t\taddr0=%08h  wdata0=%08h  wstrb0=%04b  rdata0=%08h",
                mem0_addr, mem0_wdata, mem0_wstrb, mem0_rdata);
        end
`endif

        //  load -- register write

        load1       <=  load;
        if (rdw || (load1 && mem0_ready)) begin     //  write rd
            rx[rdr]     <=  rdw ? rdx : rd_l;
            load        <=  0;
            load1       <=  0;
`ifdef CORE_DEBUG
            if  (load1)
                $write("[LOAD]");
            $display("\tx[%d]    = %08h", rdr, rdw ? rdx : rd_l);
`endif
        end

        //  fetch instruction

        if (flush_i) begin

            //  instruction cache flush
            pc_adr1     <=  BAD_ADDR;
            pc_adr2     <=  BAD_ADDR;
            pc_adr3     <=  BAD_ADDR;
            pc_get      <=  pc;
            flush_i     <=  0;

        end else begin

            if (pc_adr0 != pc_adr1) begin
                pc_adr1     <=  pc_adr0;
                pc_dat2     <=  pc_dat1;
                pc_adr2     <=  pc_adr1;
                pc_dat3     <=  pc_dat2;
                pc_adr3     <=  pc_adr2;
            end

            if  (ins_hav) begin
                ins         <=  dec_ins;
                ins_pc      <=  dec_pc;
`ifdef CORE_COMPRESSED
                ins_c       <=  dec_c;
                dec_pc      <=  dec_pc + (dec_c ? 2 : 4);
`else
                dec_pc      <=  dec_pc + 4;
`endif
            end

            if (pc_adr0[31:2] == pc[31:2] ||
                pc_adr1[31:2] == pc[31:2] ||
                pc_adr2[31:2] == pc[31:2]) begin
                if (pc_get  <= pc + 8)
                    pc_get  <=  pc_get + 4;
            end else begin
                pc_get  <=  pc;
                dec_pc  <=  pc;
            end
        end

        if (ins_ok && !load && !store && (!store1 || mem0_ready)) begin

// ===========================================================================
`ifdef CORE_PC_LOG
    $fdisplay(logf, "%h %d", pc, log_clk);
`endif
`ifdef CORE_DEBUG
    $display("x[1..] = %08h %08h %08h %08h %08h %08h %08h",
                rx[ 1], rx[ 2], rx[ 3], rx[ 4], rx[ 5], rx[ 6], rx[ 7]);
    $display("%08h %08h %08h %08h %08h %08h %08h %08h",
        rx[ 8], rx[ 9], rx[10], rx[11], rx[12], rx[13], rx[14], rx[15]);
`ifndef CORE_E16REG
    $display("%08h %08h %08h %08h %08h %08h %08h %08h",
        rx[16], rx[17], rx[18], rx[19], rx[20], rx[21], rx[22], rx[23]);
    $display("%08h %08h %08h %08h %08h %08h %08h %08h",
        rx[24], rx[25], rx[26], rx[27], rx[28], rx[29], rx[30], rx[31]);
`endif
    $display("[STEP]\t%6d\t%08h:\t%08h  rs1_w=%08h rs2_w=%08h",
        step_cnt,   pc, ins, rs1_w, rs2_w);

    step_cnt    <=  step_cnt + 1;
`endif
// ===========================================================================

            pc          <=  pc1_w;              //  default: fetch next instr
            if (dec_pc != pc1_w)                //  decoded *this* cycle ?
                dec_pc  <=  pc1_w;
            rdr         <=  dc_rd;
            rdw         <=  |dc_rd;

            ins_r       <=  ins;
            rs1_r       <=  rs1_w;
            rs2_r       <=  rs2_w;

            if (dc_op[1:0] != 2'b11)            //  low bits always 1
                trap    <=  1;

            case (dc_op[6:2])                   //  opcodes

                5'b00000: begin                                 //  <LOAD>
                    rdw         <=  0;
                    mem0_addr   <=  { ladr_w[31:2], 2'b00 };
                    ladr        <=  ladr_w[1:0];
                    lfn3        <=  dc_fn3;
                    load        <=  |dc_rd;
`ifdef  CORE_TRAP_UNALIGNED
                    if ((dc_fn3[1:0] == 2'b01 &&                //  LH / LHU
                            ladr_w[0]) ||
                        (dc_fn3 == 3'b010 &&                    //  LW
                            ladr_w[1:0] != 2'b00))
                        trap    <=  1;
`endif
                end

`ifdef  CORE_CUSTOM0
                5'b00010:   rdx <=  c0_rd_w;                    //  <Custom-0>
`endif

                5'b00011:   begin                               //  FENCE
                    rdw         <=  0;
                    ins_pc      <=  BAD_ADDR;   //  flush instruction cache
                    flush_i     <=  1;
                    pc_get      <=  pc1_w;
                end

                5'b00100: case (dc_fn3)                         //  <OP-IMM>
                    3'b000: rdx <=  rs1_w + dc_ii;              //  ADDI
                    3'b001: rdx <=  rs1_w << dc_rs2;            //  SLLI
                    3'b010: rdx <=  ci_lts ? 1 : 0;             //  SLTI
                    3'b011: rdx <=  ci_ltu ? 1 : 0;             //  SLTIU
                    3'b100: rdx <=  rs1_w ^ dc_ii;              //  XORI
                    3'b101: case (dc_fn7)
                        7'b0000000: rdx <=  rs1_w >> dc_rs2;    //  SRLI
                        7'b0100000: rdx <=                      //  SRAI
                                        $signed(rs1_w) >>> dc_rs2;
                        7'b0110000: rdx <=  (rs1_w >> dc_rs2) | //  RORI
                                            (rs1_w << (32-dc_rs2));
                        default:    trap <= 1;
                    endcase
                    3'b110: rdx <=  rs1_w | dc_ii;              //  ORI
                    3'b111: rdx <=  rs1_w & dc_ii;              //  ANDI
                endcase

                5'b00101:   rdx <=  dc_iu + pc;                 //  AUIPC

                5'b01000: begin                                 //  <STORE>
                    rdw         <=  0;
                    mem0_addr   <=  { sadr_w[31:2], 2'b00 };
                    store       <=  1;
                    case (dc_fn3)
                        3'b000: begin                           //  SB
                            mem0_wdata  <=
                                {   rs2_w[7:0], rs2_w[7:0],
                                    rs2_w[7:0], rs2_w[7:0] };
                            mem0_wstrb  <=
                                sadr_w[1:0] == 2'b00 ? 4'b0001 :
                                sadr_w[1:0] == 2'b01 ? 4'b0010 :
                                sadr_w[1:0] == 2'b10 ? 4'b0100 :
                                                       4'b1000;
                        end
                        3'b001: begin                           //  SH
                            mem0_wdata  <=
                                {   rs2_w[15:0], rs2_w[15:0] };
                            mem0_wstrb  <=
                                sadr_w[1] ? 4'b1100 : 4'b0011;
`ifdef  CORE_TRAP_UNALIGNED
                            if (sadr_w[0])
                                trap    <=  1;
`endif
                        end
                        3'b010: begin                           //  SW
                            mem0_wdata  <=  rs2_w;
                            mem0_wstrb  <=  4'b1111;
`ifdef  CORE_TRAP_UNALIGNED
                            if (sadr_w[1:0] != 2'b00)
                                trap    <=  1;
`endif
                        end
                        default:    trap <= 1;
                    endcase
                end

//              5'b01010:                                       //  <Custom-1>

                5'b01100: case (dc_fn7)                         //  <OP>
                    7'b0000000: case (dc_fn3)
                        3'b000: rdx <=  rs1_w + rs2_w;          //  ADD
                        3'b001: rdx <=  rs1_w << rs2_w[4:0];    //  SLL
                        3'b010: rdx <=  cr_lts ? 1 : 0;         //  SLT
                        3'b011: rdx <=  cr_ltu ? 1 : 0;         //  SLTU
                        3'b100: rdx <=  rs1_w ^ rs2_w;          //  XOR
                        3'b101: rdx <=  rs1_w >> rs2_w[4:0];    //  SRL
                        3'b110: rdx <=  rs1_w | rs2_w;          //  OR
                        3'b111: rdx <=  rs1_w & rs2_w;          //  AND
                    endcase

                    7'b0100000: case (dc_fn3)
                        3'b000: rdx <=  rs1_w - rs2_w;          //  SUB
                        3'b101: rdx <=  $signed(rs1_w)          //  SRA
                                                >>> rs2_w[4:0];
                        default:    trap <= 1;
                    endcase
`ifdef CORE_MULDIV
                    7'b0000001: begin                           //  <MULDIV>
                        if (m_done) begin
                            if (m_rst) begin
                                rdw     <=  0;
                                pc      <=  pc;
                            end else begin
                                rdx     <=  m_rd;
                            end
                            m_run   <=  0;
                            m_rst   <=  1;
                        end else begin
                            if (m_run) begin
                                m_go    <=  0;
                            end else begin
                                m_run   <=  1;
                                m_go    <=  1;
                            end
                            rdw     <=  0;
                            pc      <=  pc;
                        end
                    end
`endif

                    default: begin
`ifdef CORE_KRYPTO
                        if (ins[29] && dc_fn3 === 3'b000) begin
                            rdx     <=  aes_rd_w;
                        end else
`endif
                            trap    <= 1;
                    end
                endcase

                5'b01101:   rdx <=  dc_iu;                      //  LUI

                5'b11000: begin                                 //  <BRANCH>
                    rdw         <=  0;
                    if (branch) begin
                        pc      <=  jalbr_w;
                        pc_get  <=  jalbr_w;
                        dec_pc  <=  jalbr_w;
                    end
                end

                5'b11001: begin                                 //  JALR
                    rdx         <=  pc1_w;
                    pc          <=  jalr_w;
                    pc_get      <=  jalr_w;
                    dec_pc      <=  jalr_w;
                end

                5'b11011: begin                                 //  JAL
                    rdx         <=  pc1_w;
                    pc          <=  jalbr_w;
                    pc_get      <=  jalbr_w;
                    dec_pc      <=  jalbr_w;
                end

                5'b11100: begin                                 //  SYSTEM

                    if (ins == 32'h10500073) begin
                        //  WFI     10500073
                        rdw     <=  0;
                        if (irq_fl)
                            irq_fl  <=  0;
                        else
                            wfi <=  1;
                    end else begin
                        //  ECALL   00000073
                        //  EBREAK  00100073
                        //  CSRXX
                        rdw     <=  0;
                        trap    <=  1;
                    end
                end

                default: begin
                    rdw         <=  0;
                    trap        <=  1;
                end
            endcase
        end
    end
endmodule

