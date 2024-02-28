//  uart_rx.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === UART Receive

/*
    My simple UART receive interface. Implements synchronizing 8-N-1:

           (find) 1.5 BITCLKS    BITCLKS   BITCLKS
         __+___ +--------------+---------+---------+------
               \| value 0 |         |         |         |
         STOP   |  START  |  DATA0  |  DATA1  |  DATA2  |
        value 1 |\_______/|         |         |
                ^
    Roughly sync (sample freq BITCLKS/16) with falling edge after STOP bit
    (idx=8), then set timer to 1.5*BITCLKS (idx=9) to sample at the *center*
    of eight consecutive data bits (idx=0..7), BITCLKS apart.
*/

`include "config.vh"

`define TCLKS BITCLKS[TMR_LEN-1:0]

module uart_rx #(
    parameter   BITCLKS = 868,              //  100MHz / 115200 bps
    parameter   TMR_LEN = 14                //  large enough for 1.5 * BITCLKS
) (
    input wire          clk,                //  system clock
    input wire          rst,                //  reset = 1
    input wire          ack,                //  pulse high to read next byte
    output reg  [7:0]   data,               //  current data byte
    output reg          rdy,                //  1: data byte ready in data
    //  external interface
    output wire         rts,                //  RTS out (1=ready)
    input wire          rxd                 //  RX signal in
);
    assign      rts = !rdy;
    reg [TMR_LEN-1:0]   tmr;                //  timer
    reg [7:0]           rdata;              //  read data buffer
    reg [3:0]           idx;                //  index / state machine

    always @(posedge clk) begin

        if (rst) begin                      //  reset

            tmr <= 0;
            idx <= 9;
            rdy <= 0;

        end else begin

            if ( tmr != 0 ) begin

                tmr <= tmr - 1'b1;
                if (ack) begin              //  data was read
                    rdy <= 0;
                end

            end else begin

                //  new input bit either via timeout or state change

                case (idx)

                    //  data bits
                    0,1,2,3,4,5,6,7: begin
                        rdata[idx[2:0]] <= rxd;
                        idx <= idx + 1;
                        tmr <= `TCLKS - 1;  //  1.0 * BITCLKS
                    end

                    //  stop bit ?
                    8: if (rxd) begin
                        data <= rdata;
                        rdy <= 1;
                        idx <= 9;
                        tmr <= `TCLKS / 16; //  small step
                    end

                    //  start bit ?
                    9:  if (!rxd) begin
                        idx <= 0;
                        tmr <= 3 * `TCLKS / 2; //   1.5 * BITCLKS
                    end else
                        tmr <= `TCLKS / 16; //  small step

                    default:
                        idx <= 9;

                endcase

            end
        end
    end

endmodule

