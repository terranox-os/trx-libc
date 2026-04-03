//! TerranoxOS capability management extensions (Phase 6).
//!
//! Provides capability grant/revoke/query via TerranoxOS process
//! subsystem syscalls (0x0105-0x0107).

const builtin = @import("builtin");
const is_test = builtin.is_test;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Real implementations
// ---------------------------------------------------------------------------

fn cap_grant_real(pid: i64, cap_id: u64, rights: u64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.TRX_PROCESS_CAP_GRANT,
            @bitCast(pid),
            cap_id,
            rights,
        ),
    );
    return @intCast(ret);
}

fn cap_revoke_real(pid: i64, cap_id: u64) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(
            syscall.nr.TRX_PROCESS_CAP_REVOKE,
            @bitCast(pid),
            cap_id,
        ),
    );
    return @intCast(ret);
}

fn cap_query_real(pid: i64, caps: *anyopaque, count: *u32) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.TRX_PROCESS_CAP_QUERY,
            @bitCast(pid),
            @intFromPtr(caps),
            @intFromPtr(count),
        ),
    );
    return @intCast(ret);
}

// ---------------------------------------------------------------------------
// Test stubs
// ---------------------------------------------------------------------------

fn cap_grant_test(_: i64, _: u64, _: u64) c_int {
    return 0;
}

fn cap_revoke_test(_: i64, _: u64) c_int {
    return 0;
}

fn cap_query_test(_: i64, _: *anyopaque, count: *u32) c_int {
    count.* = 0;
    return 0;
}

const cap_grant_impl = if (is_test) cap_grant_test else cap_grant_real;
const cap_revoke_impl = if (is_test) cap_revoke_test else cap_revoke_real;
const cap_query_impl = if (is_test) cap_query_test else cap_query_real;

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/// Grant a capability to a process.
pub export fn trx_cap_grant(pid: i64, cap_id: u64, rights: u64) c_int {
    return cap_grant_impl(pid, cap_id, rights);
}

/// Revoke a capability from a process.
pub export fn trx_cap_revoke(pid: i64, cap_id: u64) c_int {
    return cap_revoke_impl(pid, cap_id);
}

/// Query capabilities of a process.
pub export fn trx_cap_query(pid: i64, caps: *anyopaque, count: *u32) c_int {
    return cap_query_impl(pid, caps, count);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "syscall numbers match genesis_syscall.h" {
    try testing.expectEqual(@as(usize, 0x0105), syscall.nr.TRX_PROCESS_CAP_GRANT);
    try testing.expectEqual(@as(usize, 0x0106), syscall.nr.TRX_PROCESS_CAP_REVOKE);
    try testing.expectEqual(@as(usize, 0x0107), syscall.nr.TRX_PROCESS_CAP_QUERY);
}

test "trx_cap_grant stub returns 0" {
    const ret = trx_cap_grant(1, 42, 0xFF);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "trx_cap_revoke stub returns 0" {
    const ret = trx_cap_revoke(1, 42);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "trx_cap_query stub returns 0 and sets count to 0" {
    var count: u32 = 99;
    var buf: [64]u8 = undefined;
    const ret = trx_cap_query(1, @ptrCast(&buf), &count);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(u32, 0), count);
}
