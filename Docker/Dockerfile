FROM ubuntu:noble AS builder

# Install Make, g++, verilator, the RISC-V toolchain and the picolibc library
RUN apt-get update

RUN apt-get install -qy --no-install-recommends make g++ bsdmainutils verilator gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf


# NOTE: the random forces a Docker cache miss to force
# the execution of the script
ADD "https://www.random.org/cgi-bin/randbyte?nbytes=10&format=h" skipcache

# Now compile and simulate
WORKDIR /build
COPY ./ /build

RUN USE_PICOLIBC=1 make prof 2>&1 | tee -a sloth_build.log
RUN tar -czvf docker_build.tar.gz sloth_build.log core_pc.log firmware.pmap firmware.bin  firmware.elf  firmware.hex _prof _build drv slh --transform 's,^,docker_build/,'

# Copy the produced artifacts to the host
FROM scratch AS artifacts
COPY --from=builder /build/docker_build.tar.gz ./docker_build.tar.gz
