#!/bin/bash
set -euo pipefail

LIBC_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIBC_INCLUDE="$LIBC_ROOT/include"
LIBC_LIB="$LIBC_ROOT/zig-out/lib"
KERNEL_LIBS="$LIBC_ROOT/deps/kernel-libs/genesis-abi/include"
OUT_DIR="$LIBC_ROOT/tests/integration/out"

mkdir -p "$OUT_DIR"

echo "=== Building trx-libc ==="
cd "$LIBC_ROOT"
zig build

echo "=== Compiling hello.c ==="
clang -target x86_64-unknown-none \
    -ffreestanding -nostdlib -nostdinc \
    -I"$LIBC_INCLUDE" \
    -I"$KERNEL_LIBS" \
    -c tests/integration/hello.c \
    -o "$OUT_DIR/hello.o"

echo "=== Linking against libc-x86_64.a ==="
ld.lld \
    -T tests/integration/userspace.ld \
    -o "$OUT_DIR/hello.elf" \
    "$OUT_DIR/hello.o" \
    "$LIBC_LIB/libc-x86_64.a" \
    --gc-sections

echo "=== Verifying ELF ==="
file "$OUT_DIR/hello.elf"
size "$OUT_DIR/hello.elf"

echo "=== Generating hex header ==="
xxd -i "$OUT_DIR/hello.elf" > "$OUT_DIR/hello_trxlibc_elf.h"
# Fix variable names (xxd uses full path)
sed -i "s|${OUT_DIR//\//\\/}_hello_elf|hello_trxlibc_elf|g" "$OUT_DIR/hello_trxlibc_elf.h"
sed -i "s|unsigned int|static const uint32_t|g" "$OUT_DIR/hello_trxlibc_elf.h"
sed -i "s|unsigned char|static const uint8_t|g" "$OUT_DIR/hello_trxlibc_elf.h"

echo "=== Output ==="
ls -la "$OUT_DIR/"
echo
echo "To embed in TerranoxOS kernel:"
echo "  cp $OUT_DIR/hello_trxlibc_elf.h /path/to/terranox-os/kernel/core/"
echo "  Then add a shell command to load it (see user_hello_elf.h pattern)"
