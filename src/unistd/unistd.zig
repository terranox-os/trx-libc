//! POSIX unistd.h function implementations.

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

/// Write bytes to a file descriptor.
pub export fn write(fd: c_int, buf: [*]const u8, count: usize) isize {
    return errno_mod.syscall_ret(
        syscall.syscall3(syscall.nr.WRITE, @intCast(fd), @intFromPtr(buf), count),
    );
}

/// Read bytes from a file descriptor.
pub export fn read(fd: c_int, buf: [*]u8, count: usize) isize {
    return errno_mod.syscall_ret(
        syscall.syscall3(syscall.nr.READ, @intCast(fd), @intFromPtr(buf), count),
    );
}

/// Close a file descriptor.
pub export fn close(fd: c_int) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.CLOSE, @intCast(fd)),
    );
    return @intCast(ret);
}

/// Reposition file offset.
pub export fn lseek(fd: c_int, offset: i64, whence: c_int) i64 {
    const raw = syscall.syscall3(
        syscall.nr.LSEEK,
        @intCast(fd),
        @bitCast(offset),
        @intCast(whence),
    );
    const signed: isize = @bitCast(raw);
    if (signed < 0 and signed > -4096) {
        errno_mod.errno = @intCast(-signed);
        return -1;
    }
    return @bitCast(raw);
}

/// Delete a name from the filesystem.
pub export fn unlink(path: [*:0]const u8) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.TRX_FS_UNLINK, @intFromPtr(path)),
    );
    return @intCast(ret);
}

/// Return the process ID of the calling process.
pub export fn getpid() c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall0(syscall.nr.GETPID),
    );
    return @intCast(ret);
}

/// Duplicate a file descriptor.
pub export fn dup2(oldfd: c_int, newfd: c_int) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(syscall.nr.DUP2, @intCast(oldfd), @intCast(newfd)),
    );
    return @intCast(ret);
}

/// Create a pipe.
pub export fn pipe(pipefd: *[2]c_int) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.PIPE, @intFromPtr(pipefd)),
    );
    return @intCast(ret);
}

/// sysconf constants.
const _SC_PAGE_SIZE: c_int = 30;

/// Get configurable system variables.
/// Returns hardcoded values — no syscall needed.
pub export fn sysconf(name: c_int) c_long {
    if (name == _SC_PAGE_SIZE) return 4096;
    errno_mod.errno = errno_mod.EINVAL;
    return -1;
}
