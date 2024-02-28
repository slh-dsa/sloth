//  config.vh
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === High-level RTL and Firmware configuration

`ifndef CONFIG_VH
`define CONFIG_VH

`timescale  1 ns / 1 ps
`default_nettype none

`define     SLOTH                           //  standalone configuration
`define     SLOTH_CLK   250000000           //  input clock frequency
`define     RAM_XADR    17                  //  RAM (1 << RAM_XADR) bytes

//  === cpu core options
//`define   CORE_DEBUG
//`define   CORE_CUSTOM0                    //  custom instructions
`define     CORE_COMPRESSED                 //  "c" - compressed ISA
//`define   CORE_KRYPTO                     //  "k" - cryptography
`define     CORE_MULDIV                     //  "m" - multiplication
//`define   CORE_USEDSP                     //  use fpga dsp for "m"
//`define   CORE_E16REG                     //  "e" - small register file
//`define   CORE_FPU                        //  (affects only "c" atm)
//`define   CORE_TRAP_UNALIGNED             //  trap on unaligned load/store

//  === top options
`define     SLOTH_KECCAK                    //  FIPS 202 / SHA3 & SHAKE
`define     SLOTH_SHA256                    //  FIPS 180 / SHA2-224 & 256
`define     SLOTH_SHA512                    //  FIPS 180 / SHA2-384 & 512
//`define       SLOTH_KECTI3                    //  Masked Keccak (SHA3 & SHAKE)

//  === communication pins
`define     CONF_GPIO                       //  General purpose IO
`define     CONF_UART_TX                    //  Serial transmit
`define     CONF_UART_RX                    //  Serial receive
`define     UART_BITCLKS (`SLOTH_CLK/115200) // clocks per bit

`endif
