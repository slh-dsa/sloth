//  sim_tb.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Testbench simulation (verilator / icarus verilog)

`ifdef SIM_TB
//`define SIM_UART_RX

`include "config.vh"

`ifndef VERILATOR
module clk_gen;
    /* verilator lint_off STMTDLY */
    //  clock generator
    reg     clk = 1;
    always #5 clk = ~clk;
    /* verilator lint_on STMTDLY */

    sim_tb clked (clk);
endmodule
`endif

//  externally supplied clock

module sim_tb (input wire clk);

    reg     [31:0]  cyc = 0;
    wire            rst = (cyc == 0);
    wire            trap;

    //  reset and trap
    always @(posedge clk) begin
        cyc <=  cyc + 1;
        if (trap) begin
            $display("\n[**TRAP**] %d", cyc);
            $finish;
        end
    end

    //  receive the UART signal here (slow -- bypassed by uart_tx.v)
    wire    [7:0]   srx_byte;
    wire            srx_rdy;
    reg             srx_ack = 0;

    wire            uut_txd_o;      //  out from uut
    wire            uut_cts_i;      //  ready in uut

    uart_rx #(
        .BITCLKS    (`UART_BITCLKS)
    ) rx_dec_0 (
        .clk        (clk        ),
        .rst        (rst        ),
        .ack        (srx_ack    ),
        .data       (srx_byte   ),
        .rdy        (srx_rdy    ),
        .rts        (uut_cts_i  ),
        .rxd        (uut_txd_o  )
    );

    always @(posedge clk) begin
        if  (srx_rdy && !srx_ack) begin
            $write("%c", srx_byte);
            $fflush(1);
            srx_ack <= 1;
        end else begin
            if (!srx_rdy) begin
                srx_ack <= 0;
            end
        end
    end

    //  send UART signal here

    reg [7:0]       stx_byte = 8'h40;       //  byte to be sent
    reg             stx_send;               //  enable toggle
    wire            stx_txok;               //  can send next one

    wire            uut_rts_o;              //  out from uut
    wire            uut_rxd_i;              //  in to uut

    uart_tx #(
        .BITCLKS    (`UART_BITCLKS)
    ) tx_enc_0 (
        .clk        (clk        ),
        .rst        (rst        ),
        .send       (stx_send   ),
        .data       (stx_byte   ),
        .rdy        (stx_txok   ),
        .cts        (uut_rts_o  ),
        .txd        (uut_rxd_i  )
    );

    always @(posedge clk) begin
        if (stx_txok && (cyc[15:0] == 0)) begin
            stx_byte    <=  8'h77 + { 6'b0, cyc[17:16] };
            stx_send    <=  1;
        end else begin
            stx_send    <=  0;
        end
    end

    reg [7:0]   gpio_out = 8'hFF;       //  unconnected
    wire [7:0]  gpio_in = 8'hAA;

    //  instantiate the top level module
    fpga_top fpga_top (
        .clk        (clk        ),
        .rst        (rst        ),
        .uart_txd   (uut_txd_o  ),
        .uart_rxd   (uut_rxd_i  ),
        .uart_rts   (uut_rts_o  ),
        .uart_cts   (uut_cts_i  ),
        .gpio_out   (gpio_out   ),
        .gpio_in    (gpio_in    ),
        .trap       (trap       )
    );

    reg [7:0]   gpio_old_r = 0; //  previous value
    reg [31:0]  gpio_cnt_r = 0;

    always @(posedge clk) begin
        if (gpio_out == gpio_old_r) begin
            gpio_cnt_r  <= gpio_cnt_r + 1;
        end else begin
            $display("[GPIO] %h x %d", gpio_old_r, gpio_cnt_r);
            gpio_old_r  <= gpio_out;
            gpio_cnt_r  <= 1;
        end
    end
endmodule

`endif
