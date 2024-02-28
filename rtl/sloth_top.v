//  sloth_top.v
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === sloth interconnect

`include "config.vh"

module sloth_top (
    input wire          clk,                //  clock in
    input wire          rst,                //  reset on high
    output wire         uart_txd,           //  serial output
    input wire          uart_rxd,           //  serial input
    output wire         uart_rts,           //  ready to send (accept)
    input wire          uart_cts,           //  clear to send (accept)
    output reg  [7:0]   gpio_out,           //  gpio wires out
    input wire  [7:0]   gpio_in,            //  gpio wires in
    output wire         trap,

    output wire [3:0]           wen0,       //  port a is read/write
    output wire [`RAM_XADR-3:0] addr0,
    output wire [31:0]          wdata0,
    input wire  [31:0]          rdata0,
    output wire [`RAM_XADR-3:0] addr1,      //  port b is just read (ROM)
    input wire  [31:0]          rdata1
);
    //  just to make it available
    parameter   XLEN            = 32;

    //  selector
    parameter   SEL_NONE        = 0;
    parameter   SEL_RAM         = 1;
    parameter   SEL_MMIO        = 2;
    parameter   SEL_KECTI3      = 4;
    parameter   SEL_KECCAK      = 5;
    parameter   SEL_SHA256      = 6;
    parameter   SEL_SHA512      = 7;

    //  main memory words
    parameter   RAM_BASE        = 32'h0000_0000;
    parameter   RAM_XADR        = `RAM_XADR;
    parameter   RAM_SIZE        = (1 << RAM_XADR);

    //  memory mapped registers
    parameter   MMIO_BASE       = 32'h1000_0000;
    parameter   MMIO_UART_TX    = 0;
    parameter   MMIO_UART_TXOK  = 1;
    parameter   MMIO_UART_RX    = 2;
    parameter   MMIO_UART_RXOK  = 3;
    parameter   MMIO_GET_TICKS  = 4;
    parameter   MMIO_GPIO_IN    = 5;
    parameter   MMIO_GPIO_OUT   = 6;

    //  keccak registers; sync with test_map.h
    parameter   KECTI3_BASE     = 32'h1400_0000;
    parameter   KECCAK_BASE     = 32'h1500_0000;
    parameter   SHA256_BASE     = 32'h1600_0000;
    parameter   SHA512_BASE     = 32'h1700_0000;

    //  soft reset and cycle counter logic
    reg         reset   = 1;
    reg [31:0]  cycle_count;
    reg         irq     = 0;

    wire        core_trap;

    assign      trap    = core_trap;
    wire        btn_rst = 0;//!btn[0];

    //  cycle counter / soft reset

    always @(posedge clk) begin
        if  (rst) begin
            reset   <= 1;
        end else begin
            if (reset)
                cycle_count <= 0;
            else
                cycle_count <= cycle_count + 1;
            reset   <= 0;
        end
    end

    //  cpu interface
    wire        mem0_valid;
    wire        mem0_ready;
    wire [31:0] mem0_addr;
    wire [31:0] mem0_wdata;
    wire [3:0]  mem0_wstrb;
    wire [31:0] mem0_rdata;

    wire        mem1_valid;
    wire        mem1_ready;
    wire [31:0] mem1_addr;
    wire [31:0] mem1_rdata;

    pug_rv32 #(
        .XLEN       (XLEN       ),
        .RESET_PC   ('h0000_0000),
        .RESET_SP   (RAM_SIZE-4 )
    ) cpu0 (
        .clk        (clk        ),
        .rst        (reset      ),
        .trap       (core_trap  ),
        .irq        (irq        ),
        .mem0_valid (mem0_valid ),
        .mem0_ready (mem0_ready ),
        .mem0_addr  (mem0_addr  ),
        .mem0_wdata (mem0_wdata ),
        .mem0_wstrb (mem0_wstrb ),
        .mem0_rdata (mem0_rdata ),
        .mem1_valid (mem1_valid ),
        .mem1_ready (mem1_ready ),
        .mem1_addr  (mem1_addr  ),
        .mem1_rdata (mem1_rdata )
    );

    //  select lines
    wire        ram_sel     = mem0_valid &&
                                mem0_addr[31:24] == RAM_BASE[31:24];

    wire        mmio_sel    = mem0_valid &&
                                mem0_addr[31:24] == MMIO_BASE[31:24];
`ifdef SLOTH_KECCAK
    wire        keccak_sel  =  mem0_valid &&
                                mem0_addr[31:24] == KECCAK_BASE[31:24];
`endif
`ifdef SLOTH_SHA256
    wire        sha256_sel  =  mem0_valid &&
                                mem0_addr[31:24] == SHA256_BASE[31:24];
`endif
`ifdef SLOTH_SHA512
    wire        sha512_sel  =  mem0_valid &&
                                mem0_addr[31:24] == SHA512_BASE[31:24];
`endif
`ifdef SLOTH_KECTI3
    wire        kecti3_sel  =  mem0_valid &&
                                mem0_addr[31:24] == KECTI3_BASE[31:24];
`endif

    //  === Main RAM/ROM Memory ===

    wire [31:0]     rdata_ram = rdata0;

    assign  mem1_rdata  =   rdata1;
    assign  wen0        =   ram_sel ? mem0_wstrb : 4'b0000;
    assign  addr0       =   mem0_addr[RAM_XADR - 1:2];
    assign  wdata0      =   mem0_wdata;
    assign  addr1       =   mem1_addr[RAM_XADR - 1:2];

    //  === UART (Serial) Interface ===

    //  uart tx (transmit)

`ifdef  CONF_UART_TX

    reg [7:0]       uart_out;               //  byte to be sent
    reg             uart_send;              //  enable toggle
    wire            uart_txok;              //  can send next one

`ifdef SIM_TB
    //  faster in simulation
    assign          uart_txd =  0;
    reg             tx_send1 = 0;
    assign          uart_txok = uart_cts && !tx_send1;
    always @(posedge clk) begin
        if (uart_send && !tx_send1) begin
            $write("%c", uart_out);
            $fflush(1);
        end
        tx_send1    <=  uart_send;
    end
`else
    uart_tx #(
        .BITCLKS    (`UART_BITCLKS)
    ) uart0_tx (
        .clk        (clk        ),
        .rst        (reset      ),
        .send       (uart_send  ),
        .data       (uart_out   ),
        .rdy        (uart_txok  ),
        .cts        (uart_cts   ),
        .txd        (uart_txd   )
    );
`endif
`endif

    //  uart rx (receive)

`ifdef CONF_UART_RX
    wire [7:0]      uart_data;              //  raw data
    wire            uart_rxok;              //  new byte available
    reg             uart_poll;

    uart_rx #(
        .BITCLKS    (`UART_BITCLKS)
    ) uart0_rx (
        .clk        (clk        ),
        .rst        (reset      ),
        .ack        (uart_poll  ),
        .data       (uart_data  ),
        .rdy        (uart_rxok  ),
        .rts        (uart_rts   ),
        .rxd        (uart_rxd   )
    );
`endif

    //  === MMIO ===

    reg [31:0]      rdata_mmio;

    always @(posedge clk) begin

`ifdef CONF_UART_RX
        uart_poll   <=  0;                  //  polls are up 1 cycle only
`endif
        uart_send   <=  0;

        if (mmio_sel) begin

            case (mem0_addr[7:2])

                MMIO_UART_TX: begin         //  uart transmit data
                    if (mem0_wstrb[0]) begin
                        uart_out    <=  mem0_wdata[7:0];
                        uart_send   <=  1;
                    end
                end

`ifdef CONF_UART_TX
                MMIO_UART_TXOK: begin       //  ok to transmit ?
                    rdata_mmio  <=  { 31'b0, uart_txok };
                end
`endif

`ifdef CONF_UART_RX
                MMIO_UART_RX: begin         //  read receive
                    rdata_mmio  <=  { 24'b0, uart_data };
                    uart_poll   <=  1;
                end

                MMIO_UART_RXOK:             //  full byte received ?
                    rdata_mmio  <=  { 31'b0, uart_rxok };
`endif

                MMIO_GET_TICKS:             //  get cycle counter
                    rdata_mmio  <=  cycle_count;

`ifdef CONF_GPIO
                MMIO_GPIO_IN:               //  gpio input
                    rdata_mmio  <=  { 24'b0, gpio_in };

                MMIO_GPIO_OUT:              //  gpio output
                    if (|mem0_wstrb)
                        gpio_out    <=  mem0_wdata[7:0];
`endif
`ifdef CORE_DEBUG
                default:
                    $display("[MMIO]\taddr=%08h  wdata=%08h  wstrb=%04b",
                        mem0_addr, mem0_wdata, mem0_wstrb);
`endif
            endcase
        end
    end

    //  === hash modules ===

`ifdef SLOTH_KECTI3
    wire            kecti3_irq;
    wire [31:0]     kecti3_rdata;

    kecti3_sloth kecti3_sloth_0 (
        .clk        (clk            ),
        .rst        (reset          ),
        .sel        (kecti3_sel     ),
        .irq        (kecti3_irq     ),
        .wen        (mem0_wstrb     ),
        .addr       (mem0_addr[9:2] ),
        .wdata      (mem0_wdata     ),
        .rdata      (kecti3_rdata   )
    );
`endif

`ifdef SLOTH_KECCAK
    wire            keccak_irq;
    wire [31:0]     keccak_rdata;

    keccak_sloth keccak_sloth_0 (
        .clk        (clk            ),
        .rst        (reset          ),
        .sel        (keccak_sel     ),
        .irq        (keccak_irq     ),
        .wen        (mem0_wstrb     ),
        .addr       (mem0_addr[8:2] ),
        .wdata      (mem0_wdata     ),
        .rdata      (keccak_rdata   )
    );
`endif

`ifdef SLOTH_SHA256
    wire            sha256_irq;
    wire [31:0]     sha256_rdata;

    sha256_sloth sha256_sloth_0 (
        .clk        (clk            ),
        .rst        (reset          ),
        .sel        (sha256_sel     ),
        .irq        (sha256_irq     ),
        .wen        (mem0_wstrb     ),
        .addr       (mem0_addr[8:2] ),
        .wdata      (mem0_wdata     ),
        .rdata      (sha256_rdata   )
    );
`endif

`ifdef SLOTH_SHA512
    wire            sha512_irq;
    wire [31:0]     sha512_rdata;

    sha512_sloth sha512_sloth_0 (
        .clk        (clk            ),
        .rst        (reset          ),
        .sel        (sha512_sel     ),
        .irq        (sha512_irq     ),
        .wen        (mem0_wstrb     ),
        .addr       (mem0_addr[8:2] ),
        .wdata      (mem0_wdata     ),
        .rdata      (sha512_rdata   )
    );
`endif

    //  === Interrupt sources ===

`ifdef CONF_UART_TX
    reg             oldtxok = 0;
`endif
`ifdef CONF_UART_RX
    reg             oldrxok = 0;
`endif
    reg [31:0]      mstimer = `SLOTH_CLK / 1000;

    always @(posedge clk) begin

        irq         <=  0;                  //  clear irq

        //  wake-up interrupt every 1ms
        if (mstimer == 0) begin
            mstimer <=  `SLOTH_CLK / 1000 - 1;
            irq     <=  1;
        end else begin
            mstimer <=  mstimer - 1;
        end

        //  iterrupt writing or reading becomes available
`ifdef CONF_UART_TX
        if (uart_txok && !oldtxok) begin
            irq     <=  1;
        end
        oldtxok     <=  uart_txok;
`endif

`ifdef CONF_UART_RX
        if (uart_rxok && !oldrxok) begin
            irq     <=  1;
        end
        oldrxok     <=  uart_rxok;
`endif

`ifdef SLOTH_KECTI3
        if (kecti3_irq) begin
            irq     <=  1;
        end
`endif

`ifdef SLOTH_KECCAK
        if (keccak_irq) begin
            irq     <=  1;
        end
`endif

`ifdef SLOTH_SHA256
        if (sha256_irq) begin
            irq     <=  1;
        end
`endif

`ifdef SLOTH_SHA512
        if (sha512_irq) begin
            irq     <=  1;
        end
`endif

    end

    //  memory access logic

    reg [2:0]   rdata_src   = 0;

    assign      mem0_rdata  =   rdata_src == SEL_RAM    ? rdata_ram  :
                                rdata_src == SEL_MMIO   ? rdata_mmio :
`ifdef SLOTH_KECTI3
                                rdata_src == SEL_KECTI3 ? kecti3_rdata :
`endif
`ifdef SLOTH_KECCAK
                                rdata_src == SEL_KECCAK ? keccak_rdata :
`endif
`ifdef SLOTH_SHA256
                                rdata_src == SEL_SHA256 ? sha256_rdata :
`endif
`ifdef SLOTH_SHA512
                                rdata_src == SEL_SHA512 ? sha512_rdata :
`endif
                                32'hDEAD_BEEF;

    assign      mem0_ready = 1;
    assign      mem1_ready = 1;

    //  move data

    always @(posedge clk) begin

        rdata_src           <=  ram_sel     ?   SEL_RAM :
                                mmio_sel    ?   SEL_MMIO :
`ifdef SLOTH_KECTI3
                                kecti3_sel  ?   SEL_KECTI3 :
`endif
`ifdef SLOTH_KECCAK
                                keccak_sel  ?   SEL_KECCAK :
`endif
`ifdef SLOTH_SHA256
                                sha256_sel  ?   SEL_SHA256 :
`endif
`ifdef SLOTH_SHA512
                                sha512_sel  ?   SEL_SHA512 :
`endif
                                SEL_NONE;
    end

endmodule


