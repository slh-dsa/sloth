//  fpga_ram.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === main CPU memory for FPGA targets

module fpga_ram #(
    parameter   XLEN    = 32,
    parameter   XADR    = 12,
    parameter   XSIZ    = 1 << XADR
) (
    input wire  clk,
    input wire  [3:0]       wen0,       //  port a is read/write
    input wire  [XADR-1:0]  addr0,
    input wire  [31:0]      wdata0,
    output reg  [31:0]      rdata0,
    input wire  [XADR-1:0]  addr1,      //  port b is just read ("ROM")
    output reg  [31:0]      rdata1
);
    reg [31:0] mem [0:XSIZ-1];

    initial begin
        $readmemh("firmware.hex", mem);
    end

    always @(posedge clk) begin
        rdata0 <= mem[addr0];
        if (wen0[0]) mem[addr0][ 7: 0] <= wdata0[ 7: 0];
        if (wen0[1]) mem[addr0][15: 8] <= wdata0[15: 8];
        if (wen0[2]) mem[addr0][23:16] <= wdata0[23:16];
        if (wen0[3]) mem[addr0][31:24] <= wdata0[31:24];
    end

    always @(posedge clk) begin
        rdata1 <= mem[addr1];
    end

endmodule
