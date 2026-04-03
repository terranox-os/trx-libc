//! TerranoxOS input device extensions (Phase 6).
//!
//! Provides input device enumeration, opening, event reading, and grab
//! control via TerranoxOS subsystem 6 syscalls (0x0160-0x0165).

const builtin = @import("builtin");
const is_test = builtin.is_test;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Real implementations
// ---------------------------------------------------------------------------

fn input_enumerate_real(devices: *anyopaque, count: *u32) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(
            syscall.nr.TRX_INPUT_ENUMERATE,
            @intFromPtr(devices),
            @intFromPtr(count),
        ),
    );
    return @intCast(ret);
}

fn input_open_real(dev_id: u32, flags: u32) i64 {
    const raw = syscall.syscall2(
        syscall.nr.TRX_INPUT_OPEN,
        @as(usize, dev_id),
        @as(usize, flags),
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn input_close_real(handle: i64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.TRX_INPUT_CLOSE, @bitCast(handle)),
    );
    return @intCast(ret);
}

fn input_read_events_real(handle: i64, events: *anyopaque, max: u32) i64 {
    const raw = syscall.syscall3(
        syscall.nr.TRX_INPUT_READ_EVENTS,
        @bitCast(handle),
        @intFromPtr(events),
        @as(usize, max),
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn input_grab_real(handle: i64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.TRX_INPUT_GRAB, @bitCast(handle)),
    );
    return @intCast(ret);
}

fn input_ungrab_real(handle: i64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.TRX_INPUT_UNGRAB, @bitCast(handle)),
    );
    return @intCast(ret);
}

// ---------------------------------------------------------------------------
// Test stubs
// ---------------------------------------------------------------------------

fn input_enumerate_test(_: *anyopaque, count: *u32) c_int {
    count.* = 0;
    return 0;
}

fn input_open_test(_: u32, _: u32) i64 {
    return 5; // fake handle
}

fn input_close_test(_: i64) c_int {
    return 0;
}

fn input_read_events_test(_: i64, _: *anyopaque, _: u32) i64 {
    return 0; // no events
}

fn input_grab_test(_: i64) c_int {
    return 0;
}

fn input_ungrab_test(_: i64) c_int {
    return 0;
}

const input_enumerate_impl = if (is_test) input_enumerate_test else input_enumerate_real;
const input_open_impl = if (is_test) input_open_test else input_open_real;
const input_close_impl = if (is_test) input_close_test else input_close_real;
const input_read_events_impl = if (is_test) input_read_events_test else input_read_events_real;
const input_grab_impl = if (is_test) input_grab_test else input_grab_real;
const input_ungrab_impl = if (is_test) input_ungrab_test else input_ungrab_real;

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/// Enumerate available input devices.
pub export fn trx_input_enumerate(devices: *anyopaque, count: *u32) c_int {
    return input_enumerate_impl(devices, count);
}

/// Open an input device.
pub export fn trx_input_open(dev_id: u32, flags: u32) i64 {
    return input_open_impl(dev_id, flags);
}

/// Close an input device.
pub export fn trx_input_close(handle: i64) c_int {
    return input_close_impl(handle);
}

/// Read input events from a device.
pub export fn trx_input_read_events(handle: i64, events: *anyopaque, max: u32) i64 {
    return input_read_events_impl(handle, events, max);
}

/// Grab exclusive access to an input device.
pub export fn trx_input_grab(handle: i64) c_int {
    return input_grab_impl(handle);
}

/// Release exclusive access to an input device.
pub export fn trx_input_ungrab(handle: i64) c_int {
    return input_ungrab_impl(handle);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "input syscall numbers" {
    try testing.expectEqual(@as(usize, 0x0160), syscall.nr.TRX_INPUT_ENUMERATE);
    try testing.expectEqual(@as(usize, 0x0161), syscall.nr.TRX_INPUT_OPEN);
    try testing.expectEqual(@as(usize, 0x0162), syscall.nr.TRX_INPUT_CLOSE);
    try testing.expectEqual(@as(usize, 0x0163), syscall.nr.TRX_INPUT_READ_EVENTS);
    try testing.expectEqual(@as(usize, 0x0164), syscall.nr.TRX_INPUT_GRAB);
    try testing.expectEqual(@as(usize, 0x0165), syscall.nr.TRX_INPUT_UNGRAB);
}

test "trx_input_enumerate stub returns 0" {
    var count: u32 = 99;
    var buf: [128]u8 = undefined;
    const ret = trx_input_enumerate(@ptrCast(&buf), &count);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(u32, 0), count);
}

test "trx_input_open/close stub" {
    const handle = trx_input_open(0, 0);
    try testing.expectEqual(@as(i64, 5), handle);
    const ret = trx_input_close(handle);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "trx_input_read_events stub returns 0" {
    var buf: [256]u8 = undefined;
    const count = trx_input_read_events(5, @ptrCast(&buf), 10);
    try testing.expectEqual(@as(i64, 0), count);
}

test "trx_input_grab/ungrab stub returns 0" {
    try testing.expectEqual(@as(c_int, 0), trx_input_grab(5));
    try testing.expectEqual(@as(c_int, 0), trx_input_ungrab(5));
}
