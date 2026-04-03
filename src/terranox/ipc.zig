//! TerranoxOS IPC channel and signal extensions (Phase 6).
//!
//! Provides channel-based IPC (create, send, recv, close) and kernel
//! signal objects (create, raise, wait) via TerranoxOS subsystem 3
//! syscalls (0x0130-0x0137).

const builtin = @import("builtin");
const is_test = builtin.is_test;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Syscall numbers (from genesis_syscall.h)
// ---------------------------------------------------------------------------

const TRX_CHANNEL_CREATE: usize = 0x0130;
const TRX_CHANNEL_SEND: usize = 0x0131;
const TRX_CHANNEL_RECV: usize = 0x0132;
const TRX_CHANNEL_CLOSE: usize = 0x0133;
const TRX_SIGNAL_CREATE: usize = 0x0135;
const TRX_SIGNAL_RAISE: usize = 0x0136;
const TRX_SIGNAL_WAIT: usize = 0x0137;

// ---------------------------------------------------------------------------
// Real implementations
// ---------------------------------------------------------------------------

fn channel_create_real(flags: u32, ep0: *i64, ep1: *i64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            TRX_CHANNEL_CREATE,
            @as(usize, flags),
            @intFromPtr(ep0),
            @intFromPtr(ep1),
        ),
    );
    return @intCast(ret);
}

fn channel_send_real(ep: i64, data: [*]const u8, len: usize) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            TRX_CHANNEL_SEND,
            @bitCast(ep),
            @intFromPtr(data),
            len,
        ),
    );
    return @intCast(ret);
}

fn channel_recv_real(ep: i64, buf: [*]u8, buf_len: usize) i64 {
    const raw = syscall.syscall3(
        TRX_CHANNEL_RECV,
        @bitCast(ep),
        @intFromPtr(buf),
        buf_len,
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn channel_close_real(ep: i64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(TRX_CHANNEL_CLOSE, @bitCast(ep)),
    );
    return @intCast(ret);
}

fn signal_create_real(flags: u32) i64 {
    const raw = syscall.syscall1(TRX_SIGNAL_CREATE, @as(usize, flags));
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn signal_raise_real(handle: i64, bits: u32) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(
            TRX_SIGNAL_RAISE,
            @bitCast(handle),
            @as(usize, bits),
        ),
    );
    return @intCast(ret);
}

fn signal_wait_real(handle: i64, mask: u32, timeout_ns: i64) i64 {
    const raw = syscall.syscall3(
        TRX_SIGNAL_WAIT,
        @bitCast(handle),
        @as(usize, mask),
        @bitCast(timeout_ns),
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

// ---------------------------------------------------------------------------
// Test stubs
// ---------------------------------------------------------------------------

fn channel_create_test(_: u32, ep0: *i64, ep1: *i64) c_int {
    ep0.* = 20;
    ep1.* = 21;
    return 0;
}

fn channel_send_test(_: i64, _: [*]const u8, _: usize) c_int {
    return 0;
}

fn channel_recv_test(_: i64, _: [*]u8, _: usize) i64 {
    return 0; // no data
}

fn channel_close_test(_: i64) c_int {
    return 0;
}

fn signal_create_test(_: u32) i64 {
    return 30; // fake handle
}

fn signal_raise_test(_: i64, _: u32) c_int {
    return 0;
}

fn signal_wait_test(_: i64, mask: u32, _: i64) i64 {
    return @as(i64, mask); // return the mask as signaled bits
}

const channel_create_impl = if (is_test) channel_create_test else channel_create_real;
const channel_send_impl = if (is_test) channel_send_test else channel_send_real;
const channel_recv_impl = if (is_test) channel_recv_test else channel_recv_real;
const channel_close_impl = if (is_test) channel_close_test else channel_close_real;
const signal_create_impl = if (is_test) signal_create_test else signal_create_real;
const signal_raise_impl = if (is_test) signal_raise_test else signal_raise_real;
const signal_wait_impl = if (is_test) signal_wait_test else signal_wait_real;

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/// Create a bidirectional IPC channel.
pub export fn trx_channel_create(flags: u32, ep0: *i64, ep1: *i64) c_int {
    return channel_create_impl(flags, ep0, ep1);
}

/// Send data on a channel endpoint.
pub export fn trx_channel_send(ep: i64, data: [*]const u8, len: usize) c_int {
    return channel_send_impl(ep, data, len);
}

/// Receive data from a channel endpoint.
pub export fn trx_channel_recv(ep: i64, buf: [*]u8, buf_len: usize) i64 {
    return channel_recv_impl(ep, buf, buf_len);
}

/// Close a channel endpoint.
pub export fn trx_channel_close(ep: i64) c_int {
    return channel_close_impl(ep);
}

/// Create a kernel signal object.
pub export fn trx_signal_create(flags: u32) i64 {
    return signal_create_impl(flags);
}

/// Raise bits on a signal object.
pub export fn trx_signal_raise(handle: i64, bits: u32) c_int {
    return signal_raise_impl(handle, bits);
}

/// Wait for signal bits with timeout.
pub export fn trx_signal_wait(handle: i64, mask: u32, timeout_ns: i64) i64 {
    return signal_wait_impl(handle, mask, timeout_ns);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "IPC syscall numbers" {
    try testing.expectEqual(@as(usize, 0x0130), TRX_CHANNEL_CREATE);
    try testing.expectEqual(@as(usize, 0x0131), TRX_CHANNEL_SEND);
    try testing.expectEqual(@as(usize, 0x0132), TRX_CHANNEL_RECV);
    try testing.expectEqual(@as(usize, 0x0133), TRX_CHANNEL_CLOSE);
    try testing.expectEqual(@as(usize, 0x0135), TRX_SIGNAL_CREATE);
    try testing.expectEqual(@as(usize, 0x0136), TRX_SIGNAL_RAISE);
    try testing.expectEqual(@as(usize, 0x0137), TRX_SIGNAL_WAIT);
}

test "trx_channel_create stub returns endpoints" {
    var ep0: i64 = 0;
    var ep1: i64 = 0;
    const ret = trx_channel_create(0, &ep0, &ep1);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(i64, 20), ep0);
    try testing.expectEqual(@as(i64, 21), ep1);
}

test "trx_channel_send/recv stub" {
    const msg = "hello";
    const ret = trx_channel_send(20, msg, msg.len);
    try testing.expectEqual(@as(c_int, 0), ret);

    var buf: [64]u8 = undefined;
    const n = trx_channel_recv(21, &buf, buf.len);
    try testing.expectEqual(@as(i64, 0), n);
}

test "trx_channel_close stub returns 0" {
    try testing.expectEqual(@as(c_int, 0), trx_channel_close(20));
    try testing.expectEqual(@as(c_int, 0), trx_channel_close(21));
}

test "trx_signal_create stub returns handle" {
    const handle = trx_signal_create(0);
    try testing.expectEqual(@as(i64, 30), handle);
}

test "trx_signal_raise stub returns 0" {
    const ret = trx_signal_raise(30, 0x01);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "trx_signal_wait stub returns signaled bits" {
    const bits = trx_signal_wait(30, 0x0F, 1_000_000);
    try testing.expectEqual(@as(i64, 0x0F), bits);
}
