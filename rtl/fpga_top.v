`include "config.vh"

module fpga_top (
    input wire          clk,                //  clock in
    input wire          rst,                //  reset on high
    output wire         uart_txd,           //  serial output
    input wire          uart_rxd,           //  serial input
    output wire         uart_rts,           //  ready to send (accept)
    input wire          uart_cts,           //  clear to send (accept)
    output wire [7:0]   gpio_out,           //  gpio wires out
    input wire  [7:0]   gpio_in,            //  gpio wires in
    output wire         trap
);
    parameter   XLEN            = 32;
    parameter   RAM_XADR        = `RAM_XADR;
    parameter   RAM_SIZE        = (1 << RAM_XADR);

    wire    [3:0]           wen0;
    wire    [RAM_XADR-3:0]  addr0;
    wire    [31:0]          wdata0;
    wire    [31:0]          rdata0;
    wire    [RAM_XADR-3:0]  addr1;
    wire    [31:0]          rdata1;

    //  sloth top with the memory interface

    sloth_top sloth_top_0 (
        .clk        (clk        ),
        .rst        (rst        ),
        .uart_txd   (uart_txd   ),
        .uart_rxd   (uart_rxd   ),
        .uart_rts   (uart_rts   ),
        .uart_cts   (uart_cts   ),
        .gpio_in    (gpio_in    ),
        .gpio_out   (gpio_out   ),
        .trap       (trap       ),
        .wen0       (wen0       ),
        .addr0      (addr0      ),
        .wdata0     (wdata0     ),
        .rdata0     (rdata0     ),
        .addr1      (addr1      ),
        .rdata1     (rdata1     )
    );

    //  fpga memory

    fpga_ram #(
        .XLEN       (XLEN       ),
        .XADR       (RAM_XADR - 2),
        .XSIZ       (RAM_SIZE / 4)
    ) fpga_ram_0 (
        .clk        (clk        ),
        .wen0       (wen0       ),
        .addr0      (addr0      ),
        .wdata0     (wdata0     ),
        .rdata0     (rdata0     ),
        .addr1      (addr1      ),
        .rdata1     (rdata1     )
    );
endmodule

