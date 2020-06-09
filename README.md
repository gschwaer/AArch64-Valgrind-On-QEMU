# AArch64 Valgrind on QEMU

This script will download and build a minimal AArch64 Linux, BusyBox, QEMU
and Valgrind. You will need roughly 10 GB of disk space.

Intended usage: Cache access analysis for AArch64 binaries.

## Build

On Ubuntu 18.04.1, just run:

`./build.sh`

You will probably need to update the toolchain paths:
* `CROSS_COMPILE_ELF`
* `CROSS_COMPILE_LINUX`

There may be some dependency checks missing. If you find one, please create a PR
or write an issue.

## Run

The `build.sh` script will print the proposed command at the end.

The folder `exchange` will be shared between the host FS and the QEMU guest
(/mnt).

## Details

The script is supposed to exit if any of the commands fail and builds all four
targets in the order listed below (Versions).

* Linux 5.6.16: Minimal build for AArch64. The shared folder is using Plan 9
                folder sharing over Virtio.
* Busybox 1.31.1: Standard build for AArch64
* QEMU 5.0.0: Build for AArch64 with support for virtio and kvm
* Valgrind 3.16.0: Standard build for AArch64. Note the numerous "Implementation
                   tidying-up/TODO notes" in README.aarch64.

## Analysis of Cache Accesses Using Cachegrind

`valgrind --tool=cachegrind ./my_program`

Documentation on Cachegrind can be found here:
* https://valgrind.org/docs/manual/cg-manual.html

The cache layout can be set using:
* `--I1=<size>,<associativity>,<line size>`
* `--D1=<size>,<associativity>,<line size>`
* `--LL=<size>,<associativity>,<line size>`
