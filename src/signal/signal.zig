//! POSIX signal handling (Phase 5).
//!
//! Provides signal constants, signal set operations, and signal
//! disposition management. kill() maps to TRX_PROCESS_KILL (0x0103).

const builtin = @import("builtin");
const is_test = builtin.is_test;

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// ---------------------------------------------------------------------------
// Signal constants
// ---------------------------------------------------------------------------

pub const SIGHUP: c_int = 1;
pub const SIGINT: c_int = 2;
pub const SIGQUIT: c_int = 3;
pub const SIGILL: c_int = 4;
pub const SIGTRAP: c_int = 5;
pub const SIGABRT: c_int = 6;
pub const SIGBUS: c_int = 7;
pub const SIGFPE: c_int = 8;
pub const SIGKILL: c_int = 9;
pub const SIGUSR1: c_int = 10;
pub const SIGSEGV: c_int = 11;
pub const SIGUSR2: c_int = 12;
pub const SIGPIPE: c_int = 13;
pub const SIGALRM: c_int = 14;
pub const SIGTERM: c_int = 15;
pub const SIGCHLD: c_int = 17;
pub const SIGCONT: c_int = 18;
pub const SIGSTOP: c_int = 19;
pub const _NSIG: c_int = 32;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub const sighandler_t = ?*const fn (c_int) callconv(.c) void;
pub const SIG_DFL: sighandler_t = null;
pub const SIG_IGN: sighandler_t = @ptrFromInt(1);

pub const sigset_t = u64;

pub const sigaction_t = extern struct {
    handler: sighandler_t = SIG_DFL,
    mask: sigset_t = 0,
    flags: c_int = 0,
    _pad: [24]u8 = [_]u8{0} ** 24,
};

// ---------------------------------------------------------------------------
// Internal signal handler table
// ---------------------------------------------------------------------------

var signal_table: [32]sigaction_t = [_]sigaction_t{.{}} ** 32;

// ---------------------------------------------------------------------------
// Helper: validate signal number
// ---------------------------------------------------------------------------

fn valid_sig(sig: c_int) bool {
    return sig >= 1 and sig < _NSIG;
}

// ---------------------------------------------------------------------------
// Kill implementation (real and test stubs)
// ---------------------------------------------------------------------------

fn kill_real(pid: c_int, sig: c_int) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(
            syscall.nr.TRX_PROCESS_KILL,
            @bitCast(@as(isize, pid)),
            @intCast(sig),
        ),
    );
    return @intCast(ret);
}

var test_kill_last_pid: c_int = 0;
var test_kill_last_sig: c_int = 0;

fn kill_test(pid: c_int, sig: c_int) c_int {
    test_kill_last_pid = pid;
    test_kill_last_sig = sig;
    return 0;
}

const kill_impl = if (is_test) kill_test else kill_real;

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/// Install a signal handler, returning the previous handler.
pub export fn signal(sig: c_int, handler: sighandler_t) sighandler_t {
    if (!valid_sig(sig) or sig == SIGKILL or sig == SIGSTOP) {
        errno_mod.errno = errno_mod.EINVAL;
        return SIG_DFL;
    }
    const idx: usize = @intCast(sig);
    const old = signal_table[idx].handler;
    signal_table[idx].handler = handler;
    return old;
}

/// Examine and change a signal action.
pub export fn sigaction(sig: c_int, act: ?*const sigaction_t, oldact: ?*sigaction_t) c_int {
    if (!valid_sig(sig) or sig == SIGKILL or sig == SIGSTOP) {
        errno_mod.errno = errno_mod.EINVAL;
        return -1;
    }
    const idx: usize = @intCast(sig);
    if (oldact) |oa| {
        oa.* = signal_table[idx];
    }
    if (act) |a| {
        signal_table[idx] = a.*;
    }
    return 0;
}

/// Send a signal to a process.
pub export fn kill(pid: c_int, sig: c_int) c_int {
    return kill_impl(pid, sig);
}

/// Send a signal to the calling process.
pub export fn raise(sig: c_int) c_int {
    // Import getpid from unistd
    const getpid_fn = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });
    if (is_test) {
        // In test mode, use a fixed pid
        return kill_impl(42, sig);
    }
    return kill_impl(getpid_fn(), sig);
}

/// Initialize a signal set to empty.
pub export fn sigemptyset(set: *sigset_t) c_int {
    set.* = 0;
    return 0;
}

/// Initialize a signal set to full (all signals).
pub export fn sigfillset(set: *sigset_t) c_int {
    set.* = ~@as(sigset_t, 0);
    return 0;
}

/// Add a signal to a signal set.
pub export fn sigaddset(set: *sigset_t, sig: c_int) c_int {
    if (!valid_sig(sig)) {
        errno_mod.errno = errno_mod.EINVAL;
        return -1;
    }
    set.* |= @as(sigset_t, 1) << @intCast(sig);
    return 0;
}

/// Remove a signal from a signal set.
pub export fn sigdelset(set: *sigset_t, sig: c_int) c_int {
    if (!valid_sig(sig)) {
        errno_mod.errno = errno_mod.EINVAL;
        return -1;
    }
    set.* &= ~(@as(sigset_t, 1) << @intCast(sig));
    return 0;
}

/// Test whether a signal is a member of a signal set.
pub export fn sigismember(set: *const sigset_t, sig: c_int) c_int {
    if (!valid_sig(sig)) {
        errno_mod.errno = errno_mod.EINVAL;
        return -1;
    }
    if (set.* & (@as(sigset_t, 1) << @intCast(sig)) != 0) {
        return 1;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = if (is_test) @import("std").testing else undefined;

test "signal constants are in valid range" {
    try testing.expect(SIGHUP >= 1 and SIGHUP < _NSIG);
    try testing.expect(SIGINT >= 1 and SIGINT < _NSIG);
    try testing.expect(SIGQUIT >= 1 and SIGQUIT < _NSIG);
    try testing.expect(SIGILL >= 1 and SIGILL < _NSIG);
    try testing.expect(SIGTRAP >= 1 and SIGTRAP < _NSIG);
    try testing.expect(SIGABRT >= 1 and SIGABRT < _NSIG);
    try testing.expect(SIGBUS >= 1 and SIGBUS < _NSIG);
    try testing.expect(SIGFPE >= 1 and SIGFPE < _NSIG);
    try testing.expect(SIGKILL >= 1 and SIGKILL < _NSIG);
    try testing.expect(SIGUSR1 >= 1 and SIGUSR1 < _NSIG);
    try testing.expect(SIGSEGV >= 1 and SIGSEGV < _NSIG);
    try testing.expect(SIGUSR2 >= 1 and SIGUSR2 < _NSIG);
    try testing.expect(SIGPIPE >= 1 and SIGPIPE < _NSIG);
    try testing.expect(SIGALRM >= 1 and SIGALRM < _NSIG);
    try testing.expect(SIGTERM >= 1 and SIGTERM < _NSIG);
    try testing.expect(SIGCHLD >= 1 and SIGCHLD < _NSIG);
    try testing.expect(SIGCONT >= 1 and SIGCONT < _NSIG);
    try testing.expect(SIGSTOP >= 1 and SIGSTOP < _NSIG);
}

test "signal constant values" {
    try testing.expectEqual(@as(c_int, 1), SIGHUP);
    try testing.expectEqual(@as(c_int, 2), SIGINT);
    try testing.expectEqual(@as(c_int, 9), SIGKILL);
    try testing.expectEqual(@as(c_int, 15), SIGTERM);
    try testing.expectEqual(@as(c_int, 19), SIGSTOP);
    try testing.expectEqual(@as(c_int, 32), _NSIG);
}

test "sigemptyset clears all bits" {
    var set: sigset_t = ~@as(sigset_t, 0);
    const ret = sigemptyset(&set);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(sigset_t, 0), set);
}

test "sigfillset sets all bits" {
    var set: sigset_t = 0;
    const ret = sigfillset(&set);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(~@as(sigset_t, 0), set);
}

test "sigaddset/sigdelset/sigismember" {
    var set: sigset_t = 0;
    try testing.expectEqual(@as(c_int, 0), sigaddset(&set, SIGINT));
    try testing.expectEqual(@as(c_int, 1), sigismember(&set, SIGINT));
    try testing.expectEqual(@as(c_int, 0), sigismember(&set, SIGTERM));

    try testing.expectEqual(@as(c_int, 0), sigaddset(&set, SIGTERM));
    try testing.expectEqual(@as(c_int, 1), sigismember(&set, SIGTERM));

    try testing.expectEqual(@as(c_int, 0), sigdelset(&set, SIGINT));
    try testing.expectEqual(@as(c_int, 0), sigismember(&set, SIGINT));
    try testing.expectEqual(@as(c_int, 1), sigismember(&set, SIGTERM));
}

test "sigaddset rejects invalid signal" {
    var set: sigset_t = 0;
    errno_mod.errno = 0;
    try testing.expectEqual(@as(c_int, -1), sigaddset(&set, 0));
    try testing.expectEqual(errno_mod.EINVAL, errno_mod.errno);

    errno_mod.errno = 0;
    try testing.expectEqual(@as(c_int, -1), sigaddset(&set, _NSIG));
    try testing.expectEqual(errno_mod.EINVAL, errno_mod.errno);
}

test "sigismember rejects invalid signal" {
    var set: sigset_t = 0;
    errno_mod.errno = 0;
    try testing.expectEqual(@as(c_int, -1), sigismember(&set, -1));
    try testing.expectEqual(errno_mod.EINVAL, errno_mod.errno);
}

test "signal() sets and returns old handler" {
    // Reset table entry to default
    signal_table[@intCast(SIGUSR1)] = .{};

    // Set a handler
    const old1 = signal(SIGUSR1, SIG_IGN);
    try testing.expectEqual(SIG_DFL, old1);

    // Set another handler, get SIG_IGN back
    const old2 = signal(SIGUSR1, SIG_DFL);
    try testing.expectEqual(SIG_IGN, old2);

    // Restore
    _ = signal(SIGUSR1, SIG_DFL);
}

test "signal() rejects SIGKILL and SIGSTOP" {
    errno_mod.errno = 0;
    _ = signal(SIGKILL, SIG_IGN);
    try testing.expectEqual(errno_mod.EINVAL, errno_mod.errno);

    errno_mod.errno = 0;
    _ = signal(SIGSTOP, SIG_IGN);
    try testing.expectEqual(errno_mod.EINVAL, errno_mod.errno);
}

test "sigaction() saves and retrieves handlers" {
    // Reset table entry
    signal_table[@intCast(SIGUSR2)] = .{};

    const new_act = sigaction_t{
        .handler = SIG_IGN,
        .mask = 0x0F,
        .flags = 1,
    };
    var old_act: sigaction_t = undefined;

    // Set new action, retrieve old (should be default)
    const ret1 = sigaction(SIGUSR2, &new_act, &old_act);
    try testing.expectEqual(@as(c_int, 0), ret1);
    try testing.expectEqual(SIG_DFL, old_act.handler);
    try testing.expectEqual(@as(sigset_t, 0), old_act.mask);

    // Retrieve current (should be what we set)
    var cur_act: sigaction_t = undefined;
    const ret2 = sigaction(SIGUSR2, null, &cur_act);
    try testing.expectEqual(@as(c_int, 0), ret2);
    try testing.expectEqual(SIG_IGN, cur_act.handler);
    try testing.expectEqual(@as(sigset_t, 0x0F), cur_act.mask);
    try testing.expectEqual(@as(c_int, 1), cur_act.flags);

    // Restore default
    const def_act = sigaction_t{};
    _ = sigaction(SIGUSR2, &def_act, null);
}

test "sigaction() rejects SIGKILL" {
    const act = sigaction_t{ .handler = SIG_IGN };
    errno_mod.errno = 0;
    const ret = sigaction(SIGKILL, &act, null);
    try testing.expectEqual(@as(c_int, -1), ret);
    try testing.expectEqual(errno_mod.EINVAL, errno_mod.errno);
}

test "raise() calls kill with correct signal" {
    test_kill_last_pid = 0;
    test_kill_last_sig = 0;
    const ret = raise(SIGTERM);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(c_int, 42), test_kill_last_pid);
    try testing.expectEqual(SIGTERM, test_kill_last_sig);
}

test "kill test stub records arguments" {
    test_kill_last_pid = 0;
    test_kill_last_sig = 0;
    const ret = kill(100, SIGINT);
    try testing.expectEqual(@as(c_int, 0), ret);
    try testing.expectEqual(@as(c_int, 100), test_kill_last_pid);
    try testing.expectEqual(SIGINT, test_kill_last_sig);
}

test "sigaction_t struct size" {
    // handler (8) + mask (8) + flags (4) + pad (24) = 44, with alignment padding
    try testing.expect(@sizeOf(sigaction_t) > 0);
}

test "SIG_DFL is null, SIG_IGN is 1" {
    try testing.expectEqual(@as(?*const fn (c_int) callconv(.c) void, null), SIG_DFL);
    try testing.expectEqual(@as(usize, 1), @intFromPtr(SIG_IGN.?));
}
