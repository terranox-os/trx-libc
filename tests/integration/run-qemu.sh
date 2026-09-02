#!/bin/bash
set -euo pipefail

LIBC_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OS_ROOT="${TERRANOX_OS:?Set TERRANOX_OS to a TerranoxOS checkout}"
KERNEL_LIBS="${TERRANOX_KERNEL_LIBS:-$OS_ROOT/kernel-libs}"
OS_HEADER="$OS_ROOT/kernel/core/hello_trxlibc_elf.h"
BUILD_HEADER="$LIBC_ROOT/tests/integration/out/hello_trxlibc_elf.h"
ISO="$OS_ROOT/build/terranox.iso"

if [ ! -d "$OS_ROOT/.git" ]; then
    echo "TERRANOX_OS is not a Git checkout: $OS_ROOT" >&2
    exit 1
fi
if [ ! -f "$OS_HEADER" ]; then
    echo "TerranoxOS embedding header is missing: $OS_HEADER" >&2
    exit 1
fi
if [ ! -d "$KERNEL_LIBS" ]; then
    echo "kernel-libs checkout is missing: $KERNEL_LIBS" >&2
    exit 1
fi
if ! git -C "$OS_ROOT" diff --quiet -- kernel/core/hello_trxlibc_elf.h; then
    echo "Refusing to replace a locally modified TerranoxOS ELF header" >&2
    exit 1
fi

echo "=== Building integration ELF ==="
ZIG="${ZIG:-/tmp/zig-x86_64-linux-0.15.2/zig}" \
    "$LIBC_ROOT/tests/integration/build.sh"

HEADER_BACKUP="$(mktemp)"
LOG="$(mktemp)"
cp "$OS_HEADER" "$HEADER_BACKUP"
cleanup() {
    cp "$HEADER_BACKUP" "$OS_HEADER"
    rm -f "$HEADER_BACKUP" "$LOG"
}
trap cleanup EXIT

cp "$BUILD_HEADER" "$OS_HEADER"

echo "=== Building TerranoxOS kernel with embedded ELF ==="
(cd "$OS_ROOT" && TERRANOX_KERNEL_LIBS="$KERNEL_LIBS" go run ./cmd/trx build kernel)

echo "=== Building TerranoxOS ISO ==="
(cd "$OS_ROOT" && TERRANOX_KERNEL_LIBS="$KERNEL_LIBS" go run ./cmd/trx build iso)

echo "=== Booting QEMU integration test ==="
set +e
qemu-system-x86_64 \
    -cdrom "$ISO" \
    -m 256M \
    -netdev user,id=vn0 \
    -device virtio-net-pci,netdev=vn0 \
    -serial stdio \
    -display none \
    -no-reboot \
    -cpu Haswell \
    < <(
        sleep "${TRX_QEMU_BOOT_DELAY:-15}"
        printf 'run-trxlibc\n'
    ) > "$LOG" 2>&1 &
QEMU_PID=$!
QEMU_STATUS=0
QEMU_COMPLETED=0
QEMU_TIMED_OUT=0
QEMU_TIMEOUT="${TRX_QEMU_TIMEOUT:-90}"
QEMU_DEADLINE=$((SECONDS + QEMU_TIMEOUT))

while kill -0 "$QEMU_PID" 2>/dev/null; do
    if grep -Fq "[trx-libc] ALL PASSED" "$LOG"; then
        kill "$QEMU_PID" 2>/dev/null
        QEMU_COMPLETED=1
        break
    fi
    if [ "$SECONDS" -ge "$QEMU_DEADLINE" ]; then
        kill "$QEMU_PID" 2>/dev/null
        QEMU_TIMED_OUT=1
        break
    fi
    sleep 1
done

if [ "$QEMU_COMPLETED" -eq 1 ]; then
    wait "$QEMU_PID" 2>/dev/null
    QEMU_STATUS=0
elif [ "$QEMU_TIMED_OUT" -eq 1 ]; then
    wait "$QEMU_PID" 2>/dev/null
    QEMU_STATUS=124
else
    wait "$QEMU_PID" 2>/dev/null
    QEMU_STATUS=$?
fi
cat "$LOG"
set -e

if ! grep -Fq "[trx-libc] ALL PASSED" "$LOG"; then
    echo "Integration marker was not observed (qemu status: $QEMU_STATUS)" >&2
    exit 1
fi

echo "QEMU integration suite passed."
