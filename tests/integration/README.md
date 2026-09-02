# trx-libc Kernel Integration Tests

Tests that a C program linked against trx-libc runs correctly on the
TerranoxOS kernel. The suite is intended to be run from the trx-libc checkout
with a local TerranoxOS checkout available for the temporary ELF embedding.

## Prerequisites

- Zig 0.15.2+
- clang and lld (LLVM linker)
- `qemu-system-x86_64`, `xxd`, and `file`
- TerranoxOS kernel source
- The TerranoxOS `kernel-libs` checkout, either at `TERRANOX_KERNEL_LIBS` or
  the OS checkout's `kernel-libs` directory

## Build

```bash
./tests/integration/build.sh
```

This produces:
- `out/trxlibc_integration.elf` -- static ELF64 x86_64 binary linked against
  `libc-x86_64.a`
- `out/hello_trxlibc_elf.h` -- generated hex array for kernel embedding

The compiler tools can be selected without changing the script:

```bash
TERRANOX_KERNEL_LIBS=/path/to/kernel-libs \
ZIG=/path/to/zig CLANG=clang LD_LLD=ld.lld ./tests/integration/build.sh
```

## QEMU run

`run-qemu.sh` builds the ELF, temporarily installs the generated header in a
clean TerranoxOS checkout, builds the ISO, boots QEMU, and runs the
`run-trxlibc` shell command:

```bash
TERRANOX_OS=/path/to/terranox-os \
TERRANOX_KERNEL_LIBS=/path/to/kernel-libs \
./tests/integration/run-qemu.sh
```

The script restores the OS header on exit and refuses to overwrite a header
that already has local changes. Set `TRX_QEMU_BOOT_DELAY` or
`TRX_QEMU_TIMEOUT` to tune the boot and test timeouts.

## Integration with TerranoxOS kernel

1. Copy `out/hello_trxlibc_elf.h` to `terranox-os/kernel/core/`
2. Include it in the kernel and add a shell command to load it
   (follow the pattern in `user_hello_elf.h` / shell.c)
3. Boot with `just boot` and run the test

## What it tests

The suite covers:

1. tmpfs file creation, read/write, seek, `stat`, `fstat`, close, and unlink
2. `malloc`, `calloc`, `realloc`, and free stress
3. `pthread_create`/join and shared mutex contention
4. Display enumeration, surface creation, and compositor present
5. PS/2 input enumeration, open, empty read, and close
6. `sigaction`, `kill`, and `raise` roundtrip behavior
7. IPC channel create, send, receive, and close

The display assertion validates compositor/framebuffer syscall acceptance;
the current surface ABI does not expose user-space pixel readback. Likewise,
the current kernel signal delivery path consumes an installed handler without
entering a user-space callback, so the signal test verifies disposition and
delivery status rather than callback execution.

## Register convention

Verified match between trx-libc and kernel:
- RAX = syscall number
- RDI/RSI/RDX/R10/R8/R9 = args 0-5
- RAX = return value
- RCX, R11 clobbered by SYSCALL instruction
