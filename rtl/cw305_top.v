//  cw305_top.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === Part of the side-channel measurement demo/proto.

//      parts adapted from:

/*
ChipWhisperer Artix Target - Example of connections between example registers
and rest of system.

Copyright (c) 2016-2020, NewAE Technology Inc.
All rights reserved.

ChipWhisperer Artix Target - Example frontend to USB interface.

Copyright (c) 2020, NewAE Technology Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted without restriction. Note that modules within
the project may have additional restrictions, please carefully inspect
additional licenses.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are those
of the authors and should not be interpreted as representing official policies,
either expressed or implied, of NewAE Technology Inc.
*/

`include "config.vh"

`timescale 1ns / 1ps
`default_nettype none

//  ChipWhisperer connectivity
`include "cw305_regs.vh"

module cw305_usb_reg_fe #(
    parameter pADDR_WIDTH = 21,
    parameter pBYTECNT_SIZE = 7,
    parameter pREG_RDDLY_LEN = 3
)(
    input  wire                         usb_clk,
    input  wire                         rst,

    // Interface to host
    input  wire [7:0]                   usb_din,
    output wire [7:0]                   usb_dout,
    output wire                         usb_isout,
    input  wire [pADDR_WIDTH-1:0]       usb_addr,
    input  wire                         usb_rdn,
    input  wire                         usb_wrn,
    input  wire                         usb_alen,        // unused here
    input  wire                         usb_cen,

    // Interface to registers
    output wire [pADDR_WIDTH-1:pBYTECNT_SIZE] reg_address,  // Address of register
    output wire [pBYTECNT_SIZE-1:0]     reg_bytecnt,  // Current byte count
    output reg  [7:0]                   reg_datao,    // Data to write
    input  wire [7:0]                   reg_datai,    // Data to read
    output reg                          reg_read,     // Read flag. One clock cycle AFTER this flag is high
                                                      // valid data must be present on the reg_datai bus
    output wire                         reg_write,    // Write flag. When high on rising edge valid data is
                                                      // present on reg_datao
    output wire                         reg_addrvalid // Address valid flag
);

    reg [pADDR_WIDTH-1:0] usb_addr_r;
    reg usb_rdn_r;
    reg usb_wrn_r;
    reg usb_cen_r;
    reg [pREG_RDDLY_LEN-1:0] isoutreg;

    // register USB interface inputs:
    always @(posedge usb_clk) begin
        usb_addr_r <= usb_addr;
        usb_rdn_r <= usb_rdn;
        usb_wrn_r <= usb_wrn;
        usb_cen_r <= usb_cen;
    end

    assign reg_addrvalid = 1'b1;

    // reg_address selects the register:
    assign reg_address = usb_addr_r[pADDR_WIDTH-1:pBYTECNT_SIZE];

    // reg_bytecnt selects the byte within the register:
    assign reg_bytecnt = usb_addr_r[pBYTECNT_SIZE-1:0];

    assign reg_write = ~usb_cen_r & ~usb_wrn_r;

    always @(posedge usb_clk) begin
        if (~usb_cen & ~usb_rdn)
            reg_read <= 1'b1;
        else if (usb_rdn)
            reg_read <= 1'b0;
    end

    // drive output data bus:
    always @(posedge usb_clk) begin
        if (rst) begin
            isoutreg <= 0;
        end else begin
           isoutreg[0] <= ~usb_rdn_r;
           isoutreg[pREG_RDDLY_LEN-1:1] <= isoutreg[pREG_RDDLY_LEN-2:0];
        end
    end
    assign usb_isout = (|isoutreg) | (~usb_rdn_r);

    assign usb_dout = reg_datai;

    always @(posedge usb_clk)
        reg_datao <= usb_din;

endmodule

module cw305_iut #(
    parameter pADDR_WIDTH           = 21,
    parameter pBYTECNT_SIZE         = 7,
    parameter pDONE_EDGE_SENSITIVE  = 1,
    parameter pCRYPT_TYPE           = 13,
    parameter pCRYPT_REV            = 6,
    parameter pIDENTIFY             = 8'h2e
)(

    // Interface to cw305_usb_reg_fe:
    input  wire         usb_clk,
    input  wire         iut_clk,
    input  wire         reset,
    input  wire [pADDR_WIDTH-pBYTECNT_SIZE-1:0]
                        reg_address,    // Address of register
    input  wire [pBYTECNT_SIZE-1:0]
                        reg_bytecnt,    // Current byte count
    output reg  [7:0]   read_data,      //
    input  wire [7:0]   write_data,     //
    input  wire         reg_read,       // Read flag. One clock cycle AFTER
        //  this flag is high valid data must be present on the read_data bus
    input  wire         reg_write,      // Write flag. When high on rising
        //  edge valid data is present on write_data
    input  wire         reg_addrvalid,  // Address valid flag

    // from top:
    input  wire         ext_trig_in,    //  external trigger
    output wire         iut_trig_out,   //  internal trigger (can be an ack)
    output reg  [4:0]   o_clksettings,

    //  serial "console" is pass-through
/*
    output wire         uart_tx,        //  serial output
    input wire          uart_rx,        //  serial input
*/
    output  reg         o_user_led
);

    //  chipwhisperer defined
    reg                 busy_usb = 0;
    wire [31:0]         buildtime;

    //  ==  soc instance
    wire    core_trap;

`ifdef CONF_GPIO
    wire    [7:0]   gpio_in = { 7'b0, ext_trig_in };
    wire    [7:0]   gpio_out;
    assign  iut_trig_out = gpio_out[0];
`else
    assign  iut_trig_out = 0;
`endif

    //  URX:    usb receive from host to device to host
    reg     [7:0]   urx_byte =  0;          //  [usb clk] byte from host
    reg     [7:0]   urx_idx =   0;          //  [usb clk] index of byte
    reg     [7:0]   urx_old =   0;          //  [iut clk] actually read

    //  UTX:    usb transmit from device to host
    reg     [7:0]   utx_byte =  0;          //  [iut clk] byte to host
    reg     [7:0]   utx_idx =   0;          //  [iut clk] index of byte
    reg     [7:0]   utx_pos =   0;          //  [usb clk] last accessed idx

    //  SRX:    serial receive from device to host
    wire    [7:0]   srx_byte;               //  [iut clk] byte from device
    wire            srx_rdy;                //  [iut clk] srx_byte is valid
    reg             srx_ack =   0;          //  [iut clk] ack
    wire            srx_rts;                //  [iut_clk] rx is ready

    //  signal that we're ready to receive
    wire            uut_cts_i   =   srx_rts && (utx_idx == utx_pos);

    uart_rx #(
        .BITCLKS    (`UART_BITCLKS)
    ) srx_0 (
        .clk        (iut_clk    ),
        .rst        (reset      ),
        .ack        (srx_ack    ),
        .data       (srx_byte   ),
        .rdy        (srx_rdy    ),
        .rts        (srx_rts    ),
        .rxd        (uut_txd_o  )
    );

    //  STX:    serial transmit from host to device
    reg     [7:0]   stx_byte = 8'h00;       //  [iut clk] byte to be sent
    reg             stx_send = 0;           //  [iut clk] send trigger
    wire            stx_txok;               //  [iut clk] can send next one

    uart_tx #(
        .BITCLKS    (`UART_BITCLKS)
    ) stx_0 (
        .clk        (iut_clk    ),
        .rst        (reset      ),
        .send       (stx_send   ),
        .data       (stx_byte   ),
        .rdy        (stx_txok   ),
        .cts        (uut_rts_o  ),
        .txd        (uut_rxd_i  )
    );

    always @(posedge iut_clk) begin

        //  have a byte from serial
        if  (srx_rdy && !srx_ack) begin
            utx_byte    <=  srx_byte;
            utx_idx     <=  utx_idx + 1;
            srx_ack     <=  1;
            //$write("%c", srx_byte);
            //$fflush(1);
        end else begin
            //  wait for uart to drop rdy
            if (!srx_rdy) begin
                srx_ack <= 0;
            end
        end

        //  urx: bytes from usb
        if (stx_txok && (urx_idx != urx_old)) begin
            urx_old     <=  urx_idx;
            stx_byte    <=  urx_byte;
            stx_send    <=  1;
        end else begin
            stx_send    <=  0;
        end

        if (reset) begin
            utx_byte    <=  0;
            utx_idx     <=  0;
            urx_old     <=  0;
            stx_byte    <=  0;
            srx_ack     <=  0;
            stx_send    <=  0;
        end
    end

    // write logic (USB clock domain):

    always @(posedge usb_clk) begin

        if (reg_addrvalid && reg_read) begin
            case (reg_address)
                `REG_CLKSETTINGS:   read_data   <=  o_clksettings;
                `REG_USER_LED:      read_data   <=  o_user_led;
                `REG_CRYPT_TYPE:    read_data   <=  pCRYPT_TYPE;
                `REG_CRYPT_REV:     read_data   <=  pCRYPT_REV;
                `REG_IDENTIFY:      read_data   <=  pIDENTIFY;
                `REG_BUILDTIME:     read_data   <=  buildtime[reg_bytecnt*8 +: 8];

                `REG_TX_BYTE:   begin
                                    read_data   <=  utx_byte;
                                    utx_pos     <=  utx_idx;
                                end
                `REG_TX_IDX:        read_data   <=  utx_idx;
                `REG_RX_POS:        read_data   <=  urx_old;
                default:            read_data   <=  0;
            endcase
        end else begin
            read_data <= 0;
        end

        //  writes
        if (reg_addrvalid && reg_write) begin
            case (reg_address)
                `REG_CLKSETTINGS:   o_clksettings <= write_data;
                `REG_USER_LED:      o_user_led  <=  write_data;
                `REG_RX_BYTE:       urx_byte    <=  write_data;
                `REG_RX_IDX:        urx_idx     <=  write_data;
            endcase
        end

        if (reset) begin
            urx_byte    <=  0;
            urx_idx     <=  0;
            utx_pos     <=  0;
        end
    end

    //  instantiate the top level module
    wire            uut_txd_o;
    wire            uut_rxd_i;
    wire            uut_rts_o;
    //wire          uut_cts_i;
    wire    [7:0]   gpio_in = 8'hAA;


    fpga_top fpga_top_0 (
        .clk        (iut_clk    ),
        .rst        (reset      ),
        .uart_txd   (uut_txd_o  ),
        .uart_rxd   (uut_rxd_i  ),
        .uart_rts   (uut_rts_o  ),
        .uart_cts   (uut_cts_i  ),
        .gpio_in    (gpio_in    ),
        .gpio_out   (gpio_out   ),
        .trap       (core_trap  )
    );


    //  buildtime

    `ifndef SIM_TB
    USR_ACCESSE2 buildtime_0 (
        .CFGCLK(),
        .DATA(buildtime),
        .DATAVALID()
    );
    `else
    assign buildtime = 0;
    `endif

endmodule

module cw305_clocks (
    input  wire         usb_clk,
    output wire         usb_clk_buf,
    input  wire         I_j16_sel,
    input  wire         I_k16_sel,
    input  wire [4:0]   I_clock_reg,
    input  wire         I_cw_clkin,
    input  wire         I_pll_clk1,

    output wire         O_cw_clkout,
    output wire         O_cryptoclk
);

    wire cclk_src_is_ext;
    wire cclk_output_ext;
    wire usb_clk_bufg;

    // Select crypto clock based on registers + DIP switches
    assign cclk_src_is_ext = (I_clock_reg[2:0] == 3'b001) ? 0 : //Registers = PLL1
                             (I_clock_reg[2:0] == 3'b101) ? 1 : //Registers = 20pin
                             ((I_clock_reg[0] == 1'b0) && (I_j16_sel == 1'b1)) ? 1: //DIP = 20pin
                             0; //Default PLL1

    assign cclk_output_ext = ((I_clock_reg[0] == 1'b1) && (I_clock_reg[4:3] == 2'b00)) ? 0 : //Registers = off
                             ((I_clock_reg[0] == 1'b1) && (I_clock_reg[4:3] == 2'b01)) ? 1 : //Registers = on
                             ((I_clock_reg[0] == 1'b0) && (I_k16_sel == 1'b1)) ? 1 : //DIP = on
                             0; //Default off

`ifdef SIM_TB
    assign O_cryptoclk = cclk_src_is_ext? I_cw_clkin : I_pll_clk1;
    assign O_cw_clkout = cclk_output_ext? O_cryptoclk : 1'b0;
    assign usb_clk_bufg = usb_clk;
    assign usb_clk_buf = usb_clk_bufg;
`else
    BUFGMUX_CTRL CCLK_MUX (
       .O(O_cryptoclk),    // 1-bit output: Clock output
       .I0(I_pll_clk1),    // 1-bit input: Primary clock
       .I1(I_cw_clkin),    // 1-bit input: Secondary clock
       .S(cclk_src_is_ext) // 1-bit input: Clock select for I1
    );

    ODDR CWOUT_ODDR (
       .Q(O_cw_clkout),   // 1-bit DDR output
       .C(O_cryptoclk),   // 1-bit clock input
       .CE(cclk_output_ext), // 1-bit clock enable input
       .D1(1'b1),   // 1-bit data input (positive edge)
       .D2(1'b0),   // 1-bit data input (negative edge)
       .R(1'b0),   // 1-bit reset
       .S(1'b0)    // 1-bit set
    );

    IBUFG clkibuf (
        .O(usb_clk_bufg),
        .I(usb_clk)
    );
    BUFG clkbuf(
        .O(usb_clk_buf),
        .I(usb_clk_bufg)
    );

`endif

endmodule

module cw305_top #(
    parameter pBYTECNT_SIZE = 7,
    parameter pADDR_WIDTH = 21
)(
    // USB Interface
    input wire          usb_clk,        //  Clock
    inout wire [7:0]    usb_data,       //  Data for write/read
    input wire [pADDR_WIDTH-1:0]
                        usb_addr,       //  Address
    input wire          usb_rdn,        //  !RD, 0= addr valid for read
    input wire          usb_wrn,        //  !WR, 0= data+addr valid for write
    input wire          usb_cen,        //  !CE, active low chip enable
    input wire          usb_trigger,    //  High when trigger requested

    // Buttons/LEDs on Board
    input wire          j16_sel,        //  DIP switch J16
    input wire          k16_sel,        //  DIP switch K16
    input wire          k15_sel,        //  DIP switch K15
    input wire          l14_sel,        //  DIP Switch L14
    input wire          pushbutton,     //  Pushbutton SW4 (R1 - used as reset)
    output wire         led1,           //  red LED
    output wire         led2,           //  green LED
    output wire         led3,           //  blue LED

    // PLL
    input wire          pll_clk1,       //  PLL Clock Channel #1
    //input wire        pll_clk2,       //  PLL Clock Channel #2

    //  my serial (rxd= A12, txd= a14)
    output wire         uart_txd,       //  serial output
    input wire          uart_rxd,       //  serial input

    //  sma clock out connector (T13) connected to gpio[0]
    output wire         extclk_out,

    // 20-Pin Connector Stuff
    output wire         tio_trigger,
    output wire         tio_clkout,
    input wire          tio_clkin
    );

    wire usb_clk_buf;
    wire [7:0] usb_dout;
    wire isout;
    wire [pADDR_WIDTH-pBYTECNT_SIZE-1:0] reg_address;
    wire [pBYTECNT_SIZE-1:0] reg_bytecnt;
    wire reg_addrvalid;
    wire [7:0] write_data;
    wire [7:0] read_data;
    wire reg_read;
    wire reg_write;
    wire [4:0] clk_settings;
    wire iut_clk;

    reg     rst_usb = 1;
    reg     rst_iut = 1;
    wire    reset = rst_usb || rst_iut;

    //  USB CLK Heartbeat & Reset

    reg [24:0] usb_timer_heartbeat;
    always @(posedge usb_clk_buf) begin
        usb_timer_heartbeat <= usb_timer_heartbeat + 25'd1;
        if (!pushbutton)
            rst_usb <=  1;
        else
            rst_usb <=  0;
    end

    assign led1 = usb_timer_heartbeat[24];

    //  IUT CLK Heartbeat & Reset

    reg [22:0] iut_clk_heartbeat;
    always @(posedge iut_clk) begin
        iut_clk_heartbeat <= iut_clk_heartbeat + 23'd1;
        if (!pushbutton)
            rst_iut <=  1;
        else
            rst_iut <=  0;
    end

    assign led2 = iut_clk_heartbeat[22];

    cw305_usb_reg_fe #(
        .pBYTECNT_SIZE          (pBYTECNT_SIZE),
        .pADDR_WIDTH            (pADDR_WIDTH)
    ) cw305_usb_reg_fe_0 (
        .rst                    (reset),
        .usb_clk                (usb_clk_buf),
        .usb_din                (usb_data),
        .usb_dout               (usb_dout),
        .usb_rdn                (usb_rdn),
        .usb_wrn                (usb_wrn),
        .usb_cen                (usb_cen),
        .usb_alen               (1'b0), // unused
        .usb_addr               (usb_addr),
        .usb_isout              (isout),
        .reg_address            (reg_address),
        .reg_bytecnt            (reg_bytecnt),
        .reg_datao              (write_data),
        .reg_datai              (read_data),
        .reg_read               (reg_read),
        .reg_write              (reg_write),
        .reg_addrvalid          (reg_addrvalid)
    );

    //  === CW305 IUT

    cw305_iut #(
        .pBYTECNT_SIZE          (pBYTECNT_SIZE),
        .pADDR_WIDTH            (pADDR_WIDTH)
    ) cw305_iut_0 (
        .reset                  (reset),
        .iut_clk                (iut_clk),
        .usb_clk                (usb_clk_buf),
        .reg_address            (reg_address[pADDR_WIDTH-pBYTECNT_SIZE-1:0]),
        .reg_bytecnt            (reg_bytecnt),
        .read_data              (read_data),
        .write_data             (write_data),
        .reg_read               (reg_read),
        .reg_write              (reg_write),
        .reg_addrvalid          (reg_addrvalid),
        .ext_trig_in            (usb_trigger),
        .iut_trig_out           (extclk_out),
        .o_clksettings          (clk_settings),

        //  blinkable with USB commands
        .o_user_led             (led3       )
    );

    assign usb_data = isout? usb_dout : 8'bZ;

    cw305_clocks cw305_clocks_0 (
        .usb_clk                (usb_clk),
        .usb_clk_buf            (usb_clk_buf),
        .I_j16_sel              (j16_sel),
        .I_k16_sel              (k16_sel),
        .I_clock_reg            (clk_settings),
        .I_cw_clkin             (tio_clkin),
        .I_pll_clk1             (pll_clk1),
        .O_cw_clkout            (tio_clkout),
        .O_cryptoclk            (iut_clk)
    );

endmodule

`default_nettype wire

