# CLAUDE.md

## Project Overview

trx-libc is the TerranoxOS POSIX C library, implemented in Zig. It targets the TerranoxOS 91-syscall ABI defined in kernel-libs/genesis-abi and provides a POSIX.1-2017 compatible C library for userspace programs.

## Build & Test

```bash
zig build              # build static library (x86_64-freestanding-none)
zig build test         # run host-compiled unit tests
```

## Toolchain

- **Zig**: 0.15.2 (pinned)
- **Compiler**: clang/LLVM only (no gcc)
- **Build systems**: `zig build` (primary), Bazel (planned)

## Dependencies

- **kernel-libs**: git submodule in `deps/kernel-libs` — provides `genesis_syscall.h` and `genesis_error.h` headers

## Conventions

- **Commits**: Angular/Karma style — `type(scope): subject`
- **Branching**: trunk-based development, squash merge to main
- See `trx-libc-git-workflow.md` in kernel-libs for full details
