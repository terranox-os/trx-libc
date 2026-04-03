//! TerranoxOS GPU/DRM extensions (Phase 6).
//!
//! Provides GPU device access, buffer object management, command
//! submission, and fence synchronization via TerranoxOS subsystem 7
//! syscalls (0x0170-0x0176).

const builtin = @import("builtin");
const is_test = builtin.is_test;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Real implementations
// ---------------------------------------------------------------------------

fn gpu_open_real(dev_id: u32) i64 {
    const raw = syscall.syscall1(syscall.nr.TRX_GPU_OPEN, @as(usize, dev_id));
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn gpu_close_real(handle: i64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.TRX_GPU_CLOSE, @bitCast(handle)),
    );
    return @intCast(ret);
}

fn gpu_alloc_bo_real(handle: i64, size: u64, flags: u32) u32 {
    const raw = syscall.syscall3(
        syscall.nr.TRX_GPU_ALLOC_BO,
        @bitCast(handle),
        size,
        @as(usize, flags),
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return 0; // 0 = invalid BO handle
    }
    return @intCast(raw);
}

fn gpu_free_bo_real(handle: i64, bo_handle: u32) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(
            syscall.nr.TRX_GPU_FREE_BO,
            @bitCast(handle),
            @as(usize, bo_handle),
        ),
    );
    return @intCast(ret);
}

fn gpu_submit_real(handle: i64, cmdbuf: [*]const u8, len: usize) i64 {
    const raw = syscall.syscall3(
        syscall.nr.TRX_GPU_SUBMIT,
        @bitCast(handle),
        @intFromPtr(cmdbuf),
        len,
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn gpu_wait_fence_real(fence: i64, timeout_ns: i64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(
            syscall.nr.TRX_GPU_WAIT_FENCE,
            @bitCast(fence),
            @bitCast(timeout_ns),
        ),
    );
    return @intCast(ret);
}

// ---------------------------------------------------------------------------
// Test stubs
// ---------------------------------------------------------------------------

fn gpu_open_test(_: u32) i64 {
    return 10; // fake handle
}

fn gpu_close_test(_: i64) c_int {
    return 0;
}

fn gpu_alloc_bo_test(_: i64, _: u64, _: u32) u32 {
    return 1; // fake BO handle
}

fn gpu_free_bo_test(_: i64, _: u32) c_int {
    return 0;
}

fn gpu_submit_test(_: i64, _: [*]const u8, _: usize) i64 {
    return 100; // fake fence id
}

fn gpu_wait_fence_test(_: i64, _: i64) c_int {
    return 0;
}

const gpu_open_impl = if (is_test) gpu_open_test else gpu_open_real;
const gpu_close_impl = if (is_test) gpu_close_test else gpu_close_real;
const gpu_alloc_bo_impl = if (is_test) gpu_alloc_bo_test else gpu_alloc_bo_real;
const gpu_free_bo_impl = if (is_test) gpu_free_bo_test else gpu_free_bo_real;
const gpu_submit_impl = if (is_test) gpu_submit_test else gpu_submit_real;
const gpu_wait_fence_impl = if (is_test) gpu_wait_fence_test else gpu_wait_fence_real;

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/// Open a GPU device.
pub export fn trx_gpu_open(dev_id: u32) i64 {
    return gpu_open_impl(dev_id);
}

/// Close a GPU device.
pub export fn trx_gpu_close(handle: i64) c_int {
    return gpu_close_impl(handle);
}

/// Allocate a buffer object on the GPU.
pub export fn trx_gpu_alloc_bo(handle: i64, size: u64, flags: u32) u32 {
    return gpu_alloc_bo_impl(handle, size, flags);
}

/// Free a buffer object.
pub export fn trx_gpu_free_bo(handle: i64, bo_handle: u32) c_int {
    return gpu_free_bo_impl(handle, bo_handle);
}

/// Submit a command buffer to the GPU.
pub export fn trx_gpu_submit(handle: i64, cmdbuf: [*]const u8, len: usize) i64 {
    return gpu_submit_impl(handle, cmdbuf, len);
}

/// Wait for a GPU fence to signal.
pub export fn trx_gpu_wait_fence(fence: i64, timeout_ns: i64) c_int {
    return gpu_wait_fence_impl(fence, timeout_ns);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "GPU syscall numbers" {
    try testing.expectEqual(@as(usize, 0x0170), syscall.nr.TRX_GPU_OPEN);
    try testing.expectEqual(@as(usize, 0x0171), syscall.nr.TRX_GPU_CLOSE);
    try testing.expectEqual(@as(usize, 0x0172), syscall.nr.TRX_GPU_ALLOC_BO);
    try testing.expectEqual(@as(usize, 0x0173), syscall.nr.TRX_GPU_FREE_BO);
    try testing.expectEqual(@as(usize, 0x0175), syscall.nr.TRX_GPU_SUBMIT);
    try testing.expectEqual(@as(usize, 0x0176), syscall.nr.TRX_GPU_WAIT_FENCE);
}

test "trx_gpu_open/close stub" {
    const handle = trx_gpu_open(0);
    try testing.expectEqual(@as(i64, 10), handle);
    const ret = trx_gpu_close(handle);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "trx_gpu_alloc_bo/free_bo stub" {
    const bo = trx_gpu_alloc_bo(10, 4096, 0);
    try testing.expectEqual(@as(u32, 1), bo);
    const ret = trx_gpu_free_bo(10, bo);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "trx_gpu_submit stub returns fence" {
    var cmdbuf = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const fence = trx_gpu_submit(10, &cmdbuf, cmdbuf.len);
    try testing.expectEqual(@as(i64, 100), fence);
}

test "trx_gpu_wait_fence stub returns 0" {
    const ret = trx_gpu_wait_fence(100, 1_000_000_000);
    try testing.expectEqual(@as(c_int, 0), ret);
}
