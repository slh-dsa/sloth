//  uart_tx.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === UART Transmit

//  My simple UART serial interface for sending (TX) data, 8-N-1.

module uart_tx #(
    parameter   BITCLKS = 868,          //  100Mz / 115200 bps
    parameter   TMR_LEN = 14            //  large enough for BITCLKS
) (
    input wire          clk,            //  system clock
    input wire          rst,            //  reset on low
    input wire          send,           //  send signal (pulse high)
    input wire  [7:0]   data,           //  byte to send
    output wire         rdy,            //  high when ready to send
    //  external interface
    input wire          cts,            //  CTS in (1=other side accepts)
    output reg          txd             //  TX signal out
);

    reg [TMR_LEN-1:0]   tmr;            //  must be large enough for BITCLKS
    reg [9:0]           tdata;          //  transmit buffer
    reg [3:0]           idx;            //  index to tx buffer / fsm
    reg                 fin;            //  1=done

    assign  rdy = fin && cts;

    always @(posedge clk) begin

        if (rst) begin                  //  reset

            fin <= 1;
            tmr <= 0;
            idx <= 10;
            txd <= 1;
            tdata <= { 10'b1_1111_111_1 };

        end else begin

            if (send) begin
                //  start bit = 0, 8 bits of data lsb first, stop bit = 1
                tdata <= { 1'b1, data, 1'b0 };
                fin <= 0;
                idx <= 0;
                tmr <= 0;
            end

            if (fin) begin                  //  ready to send more

                idx <= 0;
                tmr <= 0;
                txd <= 1;

            end else begin

                if (tmr == 0) begin         //  sending mode
                    if (idx == 10)
                        fin <= 1;
                    else begin
                        txd <= tdata[idx];
                        idx <= idx + 1;
                        tmr <= BITCLKS[TMR_LEN-1:0] - 1;
                    end
                end else begin
                    tmr <= tmr - 1;
                end
            end
        end
    end
endmodule

