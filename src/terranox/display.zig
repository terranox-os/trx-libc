//! TerranoxOS display/compositor/surface/buffer extensions (Phase 6).
//!
//! Provides display enumeration, mode setting, compositor, surface, and
//! buffer management via TerranoxOS subsystem 5 syscalls (0x0150-0x0159).

const builtin = @import("builtin");
const is_test = builtin.is_test;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Real implementations
// ---------------------------------------------------------------------------

fn display_enumerate_real(displays: *anyopaque, count: *u32) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(
            syscall.nr.TRX_DISPLAY_ENUMERATE,
            @intFromPtr(displays),
            @intFromPtr(count),
        ),
    );
    return @intCast(ret);
}

fn display_set_mode_real(display_id: u32, mode: *const anyopaque) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(
            syscall.nr.TRX_DISPLAY_SET_MODE,
            @as(usize, display_id),
            @intFromPtr(mode),
        ),
    );
    return @intCast(ret);
}

fn compositor_create_real(flags: u32) i64 {
    const raw = syscall.syscall1(syscall.nr.TRX_COMPOSITOR_CREATE, @as(usize, flags));
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn compositor_present_real(handle: i64, layers: *const anyopaque, count: u32) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.TRX_COMPOSITOR_PRESENT,
            @bitCast(handle),
            @intFromPtr(layers),
            @as(usize, count),
        ),
    );
    return @intCast(ret);
}

fn surface_create_real(width: u32, height: u32, format: u32, flags: u32) i64 {
    const raw = syscall.syscall4(
        syscall.nr.TRX_SURFACE_CREATE,
        @as(usize, width),
        @as(usize, height),
        @as(usize, format),
        @as(usize, flags),
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn surface_destroy_real(handle: i64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.TRX_SURFACE_DESTROY, @bitCast(handle)),
    );
    return @intCast(ret);
}

fn buffer_create_real(width: u32, height: u32, format: u32, usage: u32) i64 {
    const raw = syscall.syscall4(
        syscall.nr.TRX_BUFFER_CREATE,
        @as(usize, width),
        @as(usize, height),
        @as(usize, format),
        @as(usize, usage),
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn buffer_map_real(handle: i64, prot: u32) i64 {
    const raw = syscall.syscall2(
        syscall.nr.TRX_BUFFER_MAP,
        @bitCast(handle),
        @as(usize, prot),
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

fn buffer_unmap_real(handle: i64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.TRX_BUFFER_UNMAP, @bitCast(handle)),
    );
    return @intCast(ret);
}

// ---------------------------------------------------------------------------
// Test stubs
// ---------------------------------------------------------------------------

fn display_enumerate_test(_: *anyopaque, count: *u32) c_int {
    count.* = 0;
    return 0;
}

fn display_set_mode_test(_: u32, _: *const anyopaque) c_int {
    return 0;
}

fn compositor_create_test(_: u32) i64 {
    return 1; // fake handle
}

fn compositor_present_test(_: i64, _: *const anyopaque, _: u32) c_int {
    return 0;
}

fn surface_create_test(_: u32, _: u32, _: u32, _: u32) i64 {
    return 2; // fake handle
}

fn surface_destroy_test(_: i64) c_int {
    return 0;
}

fn buffer_create_test(_: u32, _: u32, _: u32, _: u32) i64 {
    return 3; // fake handle
}

fn buffer_map_test(_: i64, _: u32) i64 {
    return 0x1000; // fake address
}

fn buffer_unmap_test(_: i64) c_int {
    return 0;
}

const display_enumerate_impl = if (is_test) display_enumerate_test else display_enumerate_real;
const display_set_mode_impl = if (is_test) display_set_mode_test else display_set_mode_real;
const compositor_create_impl = if (is_test) compositor_create_test else compositor_create_real;
const compositor_present_impl = if (is_test) compositor_present_test else compositor_present_real;
const surface_create_impl = if (is_test) surface_create_test else surface_create_real;
const surface_destroy_impl = if (is_test) surface_destroy_test else surface_destroy_real;
const buffer_create_impl = if (is_test) buffer_create_test else buffer_create_real;
const buffer_map_impl = if (is_test) buffer_map_test else buffer_map_real;
const buffer_unmap_impl = if (is_test) buffer_unmap_test else buffer_unmap_real;

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/// Enumerate connected displays.
pub export fn trx_display_enumerate(displays: *anyopaque, count: *u32) c_int {
    return display_enumerate_impl(displays, count);
}

/// Set display mode.
pub export fn trx_display_set_mode(display_id: u32, mode: *const anyopaque) c_int {
    return display_set_mode_impl(display_id, mode);
}

/// Create a compositor instance.
pub export fn trx_compositor_create(flags: u32) i64 {
    return compositor_create_impl(flags);
}

/// Present compositor layers.
pub export fn trx_compositor_present(handle: i64, layers: *const anyopaque, count: u32) c_int {
    return compositor_present_impl(handle, layers, count);
}

/// Create a surface.
pub export fn trx_surface_create(width: u32, height: u32, format: u32, flags: u32) i64 {
    return surface_create_impl(width, height, format, flags);
}

/// Destroy a surface.
pub export fn trx_surface_destroy(handle: i64) c_int {
    return surface_destroy_impl(handle);
}

/// Create a GPU buffer.
pub export fn trx_buffer_create(width: u32, height: u32, format: u32, usage: u32) i64 {
    return buffer_create_impl(width, height, format, usage);
}

/// Map a buffer into process address space.
pub export fn trx_buffer_map(handle: i64, prot: u32) i64 {
    return buffer_map_impl(handle, prot);
}

/// Unmap a buffer from process address space.
pub export fn trx_buffer_unmap(handle: i64) c_int {
    return buffer_unmap_impl(handle);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "display syscall numbers" {
    try testing.expectEqual(@as(usize, 0x0150), syscall.nr.TRX_DISPLAY_ENUMERATE);
    try testing.expectEqual(@as(usize, 0x0151), syscall.nr.TRX_DISPLAY_SET_MODE);
    try testing.expectEqual(@as(usize, 0x0152), syscall.nr.TRX_COMPOSITOR_CREATE);
    try testing.expectEqual(@as(usize, 0x0153), syscall.nr.TRX_COMPOSITOR_PRESENT);
    try testing.expectEqual(@as(usize, 0x0154), syscall.nr.TRX_SURFACE_CREATE);
    try testing.expectEqual(@as(usize, 0x0155), syscall.nr.TRX_SURFACE_DESTROY);
    try testing.expectEqual(@as(usize, 0x0157), syscall.nr.TRX_BUFFER_CREATE);
    try testing.expectEqual(@as(usize, 0x0158), syscall.nr.TRX_BUFFER_MAP);
    try testing.expectEqual(@as(usize, 0x0159), syscall.nr.TRX_BUFFER_UNMAP);
}

test "trx_display_enumerate stub returns 0" {
    var count: u32 = 99;
    var buf: [128]u8 = undefined;
    const ret = trx_display_enumerate(@ptrCast(&buf), &count);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(u32, 0), count);
}

test "trx_display_set_mode stub returns 0" {
    var mode: [32]u8 = undefined;
    const ret = trx_display_set_mode(0, @ptrCast(&mode));
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "trx_compositor_create stub returns handle" {
    const handle = trx_compositor_create(0);
    try testing.expectEqual(@as(i64, 1), handle);
}

test "trx_surface_create/destroy stub" {
    const handle = trx_surface_create(800, 600, 0, 0);
    try testing.expect(handle > 0);
    const ret = trx_surface_destroy(handle);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "trx_buffer_create/map/unmap stub" {
    const handle = trx_buffer_create(1920, 1080, 0, 0);
    try testing.expect(handle > 0);
    const addr = trx_buffer_map(handle, 0);
    try testing.expectEqual(@as(i64, 0x1000), addr);
    const ret = trx_buffer_unmap(handle);
    try testing.expectEqual(@as(c_int, 0), ret);
}
