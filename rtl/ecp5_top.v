//  ecp5_top.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === instantiate for ulx3s_v20.lpf

module ecp5_top (
    input wire          clk,        //  clock in
    input wire  [6:0]   btn,        //  switches
    output wire [7:0]   led,        //  output (leds)
    output wire         uart_txd,   //  serial output
    input wire          uart_rxd    //  serial input
);

    reg     [7:0]   gpio_out;
    wire    [7:0]   gpio_in = { 1'b0, btn } ;
    assign  led[5:0]    =   gpio_out[5:0];

    fpga_top fpga_top_0 (
        .clk        (clk        ),
        .rst        (!btn[0]    ),
        .uart_txd   (uart_txd   ),
        .uart_rxd   (uart_rxd   ),
        .uart_rts   (led[6]     ),
        .uart_cts   (1'b1       ),
        .gpio_out   (gpio_out   ),
        .gpio_in    (gpio_in    ),
        .trap       (led[7]     )
    );

endmodule

