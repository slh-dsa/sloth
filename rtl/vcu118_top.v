//  vcu118_top.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>. See LICENSE.

//  === top module for the VCU118 board

`ifndef SIM_TB
module vcu118_top (
    input wire          clk_250mhz_p,
    input wire          clk_250mhz_n,
    output wire         usb_uart_txd_o,
    input wire          usb_uart_rxd_i,
    output wire         usb_uart_rts_o,
    input wire          usb_uart_cts_i,
    input wire          btn_rst_i,
    input wire  [4:0]   btn_i,      //  (N, E, W, S, C)
    output wire [7:0]   led_o
);
    wire        clk;

    //  Differential to single ended clock conversion
    IBUFGDS #(
        .IOSTANDARD     ("LVDS" ),
        .DIFF_TERM      ("FALSE"),
        .IBUF_LOW_PWR   ("FALSE")
    ) i_sysclk_iobuf    (
        .I  (clk_250mhz_p),
        .IB (clk_250mhz_n),
        .O  (clk  )
    );

    reg         soft_rst_r  = 1;
    reg [31:0]  sec_cnt_r   = 0;
    reg [31:0]  cyc_cnt_r   = 0;

    wire [7:0]  gpio_out;
    wire        trap_led;

    assign led_o    =   {   trap_led,
                            usb_uart_rxd_i, usb_uart_txd_o,
                            usb_uart_rts_o, usb_uart_cts_i,
                            gpio_out[0],
                            sec_cnt_r[0], cyc_cnt_r[20] };

    always @(posedge clk) begin
        if (btn_i[4] ^ btn_rst_i) begin
            soft_rst_r  <=  1;
            cyc_cnt_r   <=  0;
            sec_cnt_r   <=  0;
        end else begin
            soft_rst_r  <=  0;
            if (cyc_cnt_r == `SLOTH_CLK - 1) begin
                cyc_cnt_r   <=  0;
                sec_cnt_r   <=  sec_cnt_r + 1;
            end else begin
                cyc_cnt_r   <=  cyc_cnt_r + 1;
            end
        end
    end

    wire [7:0]  gpio_in = { sec_cnt_r[2:0], btn_i[4:0] };

    //  Instantiate
    fpga_top fpga_top_0 (
        .clk        (clk            ),
        .rst        (soft_rst_r     ),
        .uart_txd   (usb_uart_txd_o ),
        .uart_rxd   (usb_uart_rxd_i ),
        .uart_rts   (~usb_uart_rts_o),
        .uart_cts   (~usb_uart_cts_i),
        .gpio_out   (gpio_out       ),
        .gpio_in    (gpio_in        ),
        .trap       (trap_led       )
    );

endmodule
`endif
