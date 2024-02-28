//  mem_block.vh
//  Markku-Juhani O. Saarinen <mjos@iki.fi>.  See LICENSE.

//  === assigning long blocks of registers

`ifndef _MEM_BLOCK_VH_
`define _MEM_BLOCK_VH_

`define MEM_BLOCK_4(i) { mem[i + 3], mem[i + 2], mem[i + 1], mem[i] }
`define MEM_BLOCK_6(i) { mem[i + 5], mem[i + 4], `MEM_BLOCK_4(i) }
`define MEM_BLOCK_8(i) { `MEM_BLOCK_4(i + 4), `MEM_BLOCK_4(i) }
`define MEM_BLOCK_10(i) { `MEM_BLOCK_6(i + 4), `MEM_BLOCK_4(i) }
`define MEM_BLOCK_16(i) { `MEM_BLOCK_8(i + 8), `MEM_BLOCK_8(i) }
`define MEM_BLOCK_32(i) { `MEM_BLOCK_16(i + 16), `MEM_BLOCK_16(i) }
`define MEM_BLOCK_50(i) { `MEM_BLOCK_10(i + 40), `MEM_BLOCK_10(i + 30), \
    `MEM_BLOCK_10(i + 20), `MEM_BLOCK_10(i + 10),   `MEM_BLOCK_10(i)    }

`endif
