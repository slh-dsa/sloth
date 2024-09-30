#       SLotH

An accelerator / codesign for SLH-DSA ("Stateless Hash-Based Digital Signature Standard") as described in [FIPS 205 Initial Public Draft](https://doi.org/10.6028/NIST.FIPS.205.ipd) from August 2023.

To cite this work, and the related [CRYPTO 2024 Paper](https://eprint.iacr.org/2024/367), please use:
```
@InProceedings{   Sa24,
  author        = {Markku-Juhani O. Saarinen},
  title         = {Accelerating {SLH}-{DSA} by Two Orders of Magnitude with a
                  Single Hash Unit},
  booktitle     = {Advances in Cryptology - {CRYPTO} 2024 - 44th Annual
                  International Cryptology Conference, {CRYPTO} 2024, Santa
                  Barbara, CA, USA, August 18-2, 2024, Proceedings},
  note          = {Available as IACR ePrint Report 2024/367},
  url           = {https://eprint.iacr.org/2024/367},
  pages         = {to appear},
  year          = {2024}
}
```

##      Downloading

To clone the repository:
```
git clone https://github.com/slh-dsa/sloth.git
```

What's where
```
sloth
├── slh             # Self-Contained C Implementation of SLH-DSA
├── rtl             # Verilog HDL source code
├── drv             # Accelerator drivers and test code
├── kat             # SLH-DSA Known Answer Test data
├── flow            # Misc files for FPGA and ASIC flows
├── Makefile        # Convenience Makefile for the Accelerator
├── LICENSE
└── README.md
```

##      Core SLH-DSA Algorithm in ANSI C

The SLotH accelerator uses a core SLH-DSA algorithm implementation contained in the
[slh](slh) directory. The core implementation is self-contained ANSI C code and should be able to run on pretty much any target. There are no prerequisites except for `make` and a C compiler.
```
cd sloth/slh
make test
```
See [slh/README.md](slh/README.md) for more information.


##      Verilator Simulation

As a prerequisite for simulation, you'll need:

*   [Verilator](https://github.com/verilator/verilator) verilog simulator. This might be packaged on some Linux distros.
*   A RISC-V cross-compiler that supports bare-metal targets. You can build a suitable [riscv-gnu-toolchain](https://github.com/riscv/riscv-gnu-toolchain)
with `./configure --enable-multilib` and `make newlib`. Under some Linux based distros (such as Debian), it is possible to use the packaged
`gcc-riscv64-unknown-elf` along with the packaged `picolibc-riscv64-unknown-elf`: note that in this case, you will have to export the `USE_PICOLIBC=1` environment
variable when compiling: `USE_PICOLIBC=1 make veri` (this is due to some divergence between `newlib` and `picolibc` C standard libraries linking scripts).

The name of your toolchain is set in `XCHAIN` variable in the [Makefile](Makefile).

To build and run a quick end-to-end test, try:
```
make veri
```
After a successful compilation the output should look something like this:
```
./_build/Vsim_tb
[GPIO] 00 x          0

[RESET]    ______        __  __ __
          / __/ /  ___  / /_/ // /  SLotH Accelerator Test 2024/05
         _\ \/ /__/ _ \/ __/ _  /   SLH-DSA / FIPS 205 ipd
        /___/____/\___/\__/_//_/    markku-juhani.saarinen@tuni.fi

[INFO]  === Basic health test ===
[CLK]   775     sha256_compress()
[PASS]  sha256 ( chk= 55F39AFA )
[CLK]   1462    sha512_compress()
[PASS]  sha512 ( chk= 1F59A287 )
[CLK]   1467    keccak_f1600()
[PASS]  shake256 ( chk= 07C97065 )

[INFO]  === Testbench ===
[INFO]  SLH-DSA-SHAKE-128f
[INFO]  kat test count = 0
[CLK]   SLH-DSA-SHAKE-128f 204310 slh_keygen()
[STK]   SLH-DSA-SHAKE-128f 3156 slh_keygen()
[PASS]  sk ( chk= BCA6B2C3 )
[CLK]   SLH-DSA-SHAKE-128f 4943111 slh_sign()
[STK]   SLH-DSA-SHAKE-128f 3380 slh_sign()
[PASS]  sm ( chk= C03DA016 )
[CLK]   SLH-DSA-SHAKE-128f 434660 slh_verify()
[STK]   SLH-DSA-SHAKE-128f 3284 slh_verify()
[PASS]  slh_verify() flip bit = 12389
[PASS]  All tests ok.

UART Test. Press x to exit.
GPIO 0xAA
UART 0x78 x


exit()

[**TRAP**]    8392281
- rtl/sim_tb.v:36: Verilog $finish
```
The readout from this particular execution of SLH-DSA-SHAKE-128f is that KeyGen was 204310 cycles, signing was 4943111 cycles, and verification was 434660 cycles. Furthermore, the self-tests were a PASS; the output matched the Known Answer Tests. Modify the end of `test_bench.c` to have broader test behavior.

##  Using Docker

Alternatively, it is possible to use an Ubuntu based Docker container for the simulation (with preinstalled verilator and toolchain). Having Docker installed, simply execute:


```
DOCKER_VERBOSE=1 make -f Makefile.docker
```

This will put the compilation and profiling artifacts in the compressed `Docker/docker_build.tar.gz` file.

##  Some other targets

*   `make prog_cw305`: Create and program the bitstream on CW305 (program using ChipWhisperer.)
*   `make prog_vcu118`:  Ditto for  on VCU118 (program using Vivado's hardware manager.)
*   `make synth`:  Run a Nangate45 synthesis and timing (using Yosys/OpenSTA. See [flow/yosys-sys](flow/yosys-syn).)
*   `make prof`:     Profiling (see the per-code line instruction counts in annotated source files created in directory `_prof`).


##  Side-Channel Collection

I collect traces from the 20dB low amplified SMA connector (X4). Bit 0 of the GPIO register connects to the SMA connector T13 "CLKOUT" on the board, and this is used as a trigger by `test_leak.c`. The trace collection and analysis stuff is not included, and anyway works only with my oscilloscope.
