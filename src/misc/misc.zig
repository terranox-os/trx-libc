//! Miscellaneous POSIX functions.

const syscall = @import("../internal/syscall.zig");

/// Terminate the calling process.
pub export fn _exit(status: c_int) noreturn {
    _ = syscall.syscall1(syscall.linux.EXIT, @intCast(status));
    unreachable;
}
