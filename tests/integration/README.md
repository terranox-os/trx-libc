# trx-libc Kernel Integration Test

Tests that a C program linked against trx-libc runs correctly on the
TerranoxOS kernel.

## Prerequisites

- Zig 0.15.2+
- clang (from terranox-toolchain-musl Docker image)
- lld (LLVM linker)
- TerranoxOS kernel source (for embedding the test binary)

## Build

```bash
./tests/integration/build.sh
```

This produces:
- `out/hello.elf` -- static ELF64 x86_64 binary linked against libc-x86_64.a
- `out/hello_trxlibc_elf.h` -- hex array for kernel embedding

## Integration with TerranoxOS kernel

1. Copy `out/hello_trxlibc_elf.h` to `terranox-os/kernel/core/`
2. Include it in the kernel and add a shell command to load it
   (follow the pattern in `user_hello_elf.h` / shell.c)
3. Boot with `just boot` and run the test

## What it tests

1. `write()` to stdout (syscall 0x0001)
2. `getpid()` (syscall 0x0006)
3. `malloc()` + `free()` (backed by syscall 0x0003 MMAP)
4. `strlen()`, `strcpy()` (pure computation)
5. `__errno_location()` (thread-local errno)
6. `_exit()` via `return 0` from main (CRT startup)

## Register convention

Verified match between trx-libc and kernel:
- RAX = syscall number
- RDI/RSI/RDX/R10/R8/R9 = args 0-5
- RAX = return value
- RCX, R11 clobbered by SYSCALL instruction
