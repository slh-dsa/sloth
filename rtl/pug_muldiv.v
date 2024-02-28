//  pug_muldiv.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === RV32M extension: multiplication/division instructions

`include "config.vh"

`ifdef  CORE_MULDIV

`ifdef  CORE_USEDSP

//  Compute 64-bit result res = a * b. "a_sgn" and "b_sgn" are flags
//  telling the operation if "a" and/or "b" are signed. Try infer DSP.

module mulsig32(
    input wire          clk,
    input wire          go,
    input wire          rst,
    output reg          done = 0,
    output reg  [63:0]  res,
    input wire  [31:0]  a,
    input wire          a_sgn,
    input wire  [31:0]  b,
    input wire          b_sgn
);

    reg [31:0]  r_hi, x, y;         //  output high word, inputs
    reg [63:0]  prod;               //  product
    reg         run = 0;


    always @(posedge clk) begin

        if (rst) begin              //  reset

            done    <=  0;
            run     <=  0;

        end else if (go) begin      //  start

            prod    <=  a * b ;
            run     <=  1;

        end else if (run) begin     //  multiply step(s)

            run     <=  0;
            done    <=  1;
            res     <=  {   prod[63:32] - (a_sgn && a[31] ? b : 32'b0)
                            - (b_sgn && b[31] ? a : 32'b0), prod[31:0] };
        end
    end

endmodule

`else

//  Compute 64-bit result res = a * b. "a_sgn" and "b_sgn" are flags
//  telling the operation if "a" and/or "b" are signed. No DSP; 32 cycles.

module mulsig32(
    input wire          clk,
    input wire          go,
    input wire          rst,
    output reg          done = 0,
    output reg [63:0]   res,
    input wire [31:0]   a,
    input wire          a_sgn,
    input wire [31:0]   b,
    input wire          b_sgn
);

    reg [31:0]  x;
    reg [63:0]  y;
    reg [5:0]   pos;
    reg         run = 0;


    always @(posedge clk) begin

        if  (rst) begin

            done    <=  0;
            run     <=  0;
            pos     <=  0;

        end else if (go) begin

            //  signed initialization
            res[63:32]  <=  -(a_sgn && a[31] ? b : 0)
                            -(b_sgn && b[31] ? a : 0);
            res[31: 0]  <=  0;

            x   <=  a;
            y   <=  {32'b0, b};
            pos <=  31;
            run <=  1;

        end else if (run) begin

            if (x[0]) begin
                res <=  res + y;
            end
            x   <=  x >> 1;
            y   <=  y << 1;

            if (pos != 0) begin
                pos     <=  pos - 1;
            end else begin
                run     <=  0;
                done    <=  1;
            end

        end
    end
endmodule

`endif

//  Compute div = num / dem, res = num % dem. Signed if "sig" set.
//  Start on "sel", flag "done" at the end. Caller needs to set "rst".

module divrem32(
    input wire          clk,
    input wire          go,
    input wire          rst,
    output reg          done = 0,
    output wire [31:0]  div_o,
    output wire [31:0]  rem_o,
    input wire  [31:0]  num,
    input wire  [31:0]  dem,
    input wire          sgn
);

    reg [31:0]  div, rem, x, y;
    reg [4:0]   pos;
    reg         fld, flr, run;

    wire [31:0] t   = { rem[30:0], x[pos] };
    wire [32:0] u   = t - y;

    //  flip output values if needed
    assign  div_o   = fld ? -div : div;
    assign  rem_o   = flr ? -rem : rem;

    always @(posedge clk) begin

        if  (rst) begin

            done    <=  0;
            run     <=  0;

        end else if (go) begin

            //  absolute values for signed, store signs
            x   <=  sgn && num[31] ? -num : num;
            y   <=  sgn && dem[31] ? -dem : dem;
            fld <=  sgn && (num[31] ^ dem[31]);
            flr <=  sgn && num[31];

            div <=  0;
            rem <=  0;
            pos <=  31;
            run <=  1;

        end else if (run) begin

            rem         <=  u[32] ? t : u[31:0];
            div[pos]    <= ~u[32];

            if (pos != 0) begin
                pos     <=  pos - 1;
            end else begin
                run     <=  0;
                done    <=  1;
            end

        end
    end
endmodule


//  RV32M   multiply/divide extension

module pug_muldiv(
    input wire          clk,
    input wire          go,
    input wire          rst,
    output reg          done,
    output reg  [31:0]  rd,
    input wire  [31:0]  rs1,
    input wire  [31:0]  rs2,
    input wire  [2:0]   fn3
);
    wire [63:0] res;                                //  big multiply result
    wire [31:0] div, rem;                           //  div, remainder results
    reg         div0, oflo;
    wire        mul_done, div_done;                 //  done flags

    //  note; done flag only matters if selected

    always @(posedge clk) begin

        if (rst) begin

            div0    <=  0;
            oflo    <=  0;
            done    <=  0;

        end else if (go) begin

            //  division or remainder by zero
            div0    <=  fn3[2] && rs2 == 32'h00000000;

            //  signed divide/remainder overflow
            oflo    <=  fn3[2] && rs1 == 32'h80000000 && rs2 == 32'hFFFFFFFF;

        end else if (!done && (mul_done || div_done || div0 || oflo)) begin

            done <= 1;
            rd  <=  div0    ? (fn3[1] ? rs1 : 32'hFFFFFFFF) :
                    oflo    ? { 1'b1 ^ fn3[0] ^ fn3[1], 31'b0 } :
                    fn3[2:1] == 2'b10 ? div :       //  DIV, DIVU
                    fn3[2:1] == 2'b11 ? rem :       //  REM, REMU
                    fn3 == 3'b000 ? res[31:0] : //  MUL
                    res[63:32];                     //  MULH, MULHSU, MULHU
        end
    end

    //  (signed) multiply
    mulsig32 muls(
        .clk    (clk),
        .go     (go && !fn3[2]),
        .rst    (rst),
        .done   (mul_done),
        .res    (res),
        .a      (rs1),
        .a_sgn  (!(fn3[0] && fn3[1])),
        .b      (rs2),
        .b_sgn  (!fn3[1])
    );

    //  divide and remainder
    divrem32 divr(
        .clk    (clk),
        .go     (go && fn3[2] && !(div0 || oflo)),
        .rst    (rst),
        .done   (div_done),
        .div_o  (div),
        .rem_o  (rem),
        .num    (rs1),
        .dem    (rs2),
        .sgn    (!fn3[0])
    );

endmodule

`endif
