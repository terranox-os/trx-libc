//! POSIX poll/select I/O multiplexing (Phase 4).
//!
//! poll() maps to GEN_SYS_POLL (0x0016) shared syscall.
//! TerranoxOS also provides trx_event_wait_many (0x0139) for
//! channel-level multiplexing; poll uses the shared syscall.

const builtin = @import("builtin");
const is_test = builtin.is_test;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

pub const POLLIN: c_short = 0x0001;
pub const POLLPRI: c_short = 0x0002;
pub const POLLOUT: c_short = 0x0004;
pub const POLLERR: c_short = 0x0008;
pub const POLLHUP: c_short = 0x0010;
pub const POLLNVAL: c_short = 0x0020;

// ---------------------------------------------------------------------------
// Structures
// ---------------------------------------------------------------------------

pub const pollfd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

// ---------------------------------------------------------------------------
// Poll implementation (real and test stubs)
// ---------------------------------------------------------------------------

fn poll_real(fds: [*]pollfd, nfds: u32, timeout: c_int) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.POLL,
            @intFromPtr(fds),
            @as(usize, nfds),
            @bitCast(@as(isize, timeout)),
        ),
    );
    return @intCast(ret);
}

fn poll_test(_: [*]pollfd, _: u32, _: c_int) c_int {
    return 0; // no fds ready
}

const poll_impl = if (is_test) poll_test else poll_real;

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/// Wait for events on a set of file descriptors.
export fn poll(fds: [*]pollfd, nfds: u32, timeout: c_int) c_int {
    return poll_impl(fds, nfds, timeout);
}

/// select(2) — convert fd_sets to pollfd array and call poll.
/// TODO: Implement fd_set conversion. Stubbed with -ENOSYS for Phase 4.
export fn select(nfds: c_int, readfds: ?*anyopaque, writefds: ?*anyopaque, exceptfds: ?*anyopaque, timeout: ?*anyopaque) c_int {
    _ = nfds;
    _ = readfds;
    _ = writefds;
    _ = exceptfds;
    _ = timeout;
    errno_mod.errno = errno_mod.ENOSYS;
    return -1;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "pollfd struct size is 8 bytes" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(pollfd));
}

test "POLL* constants" {
    try testing.expectEqual(@as(c_short, 0x0001), POLLIN);
    try testing.expectEqual(@as(c_short, 0x0004), POLLOUT);
    try testing.expectEqual(@as(c_short, 0x0008), POLLERR);
    try testing.expectEqual(@as(c_short, 0x0010), POLLHUP);
    try testing.expectEqual(@as(c_short, 0x0020), POLLNVAL);
}

test "poll test stub returns 0" {
    var fds = [_]pollfd{.{
        .fd = 3,
        .events = POLLIN,
        .revents = 0,
    }};
    const ret = poll(&fds, 1, 0);
    try testing.expectEqual(@as(c_int, 0), ret);
}

test "select returns -ENOSYS" {
    errno_mod.errno = 0;
    const ret = select(0, null, null, null, null);
    try testing.expectEqual(@as(c_int, -1), ret);
    try testing.expectEqual(errno_mod.ENOSYS, errno_mod.errno);
}

test "pollfd field offsets" {
    // fd at offset 0, events at offset 4, revents at offset 6
    try testing.expectEqual(@as(usize, 0), @offsetOf(pollfd, "fd"));
    try testing.expectEqual(@as(usize, 4), @offsetOf(pollfd, "events"));
    try testing.expectEqual(@as(usize, 6), @offsetOf(pollfd, "revents"));
}
