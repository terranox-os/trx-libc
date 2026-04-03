//! POSIX errno definitions and syscall return value translation.
//!
//! The TerranoxOS kernel returns -errno in rax at the syscall boundary.
//! This module translates that to the POSIX convention: return -1 and
//! set a thread-local errno.

/// Thread-local errno. In freestanding mode (Phase 0), this is a global.
/// Phase 3 (pthreads) will replace with proper TLS via FS register.
pub var errno: c_int = 0;

/// Translate a raw syscall return value to POSIX convention.
/// If the kernel returned a negative value (> -4096), set errno and return -1.
/// Otherwise return the value as-is.
pub fn syscall_ret(raw: usize) isize {
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno = @intCast(-signed);
        return -1;
    }
    return signed;
}

// POSIX errno constants
pub const EPERM: c_int = 1;
pub const ENOENT: c_int = 2;
pub const ESRCH: c_int = 3;
pub const EINTR: c_int = 4;
pub const EIO: c_int = 5;
pub const EBADF: c_int = 9;
pub const EAGAIN: c_int = 11;
pub const ENOMEM: c_int = 12;
pub const EACCES: c_int = 13;
pub const EFAULT: c_int = 14;
pub const EBUSY: c_int = 16;
pub const EEXIST: c_int = 17;
pub const EINVAL: c_int = 22;
pub const EPIPE: c_int = 32;
pub const ENOSYS: c_int = 38;
pub const ETIMEDOUT: c_int = 110;

/// Exported for C compatibility: programs calling __errno_location()
pub export fn __errno_location() *c_int {
    return &errno;
}

test "syscall_ret success" {
    const testing = @import("std").testing;
    errno = 0;
    const ret = syscall_ret(42);
    try testing.expectEqual(@as(isize, 42), ret);
    try testing.expectEqual(@as(c_int, 0), errno);
}

test "syscall_ret error" {
    const testing = @import("std").testing;
    errno = 0;
    // Kernel returns -EINVAL (= -(22) as usize via two's complement)
    const raw: usize = @bitCast(@as(isize, -22));
    const ret = syscall_ret(raw);
    try testing.expectEqual(@as(isize, -1), ret);
    try testing.expectEqual(@as(c_int, 22), errno); // EINVAL
}
