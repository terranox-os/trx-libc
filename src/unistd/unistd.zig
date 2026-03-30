//! POSIX unistd.h function implementations.

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

/// Write bytes to a file descriptor.
export fn write(fd: c_int, buf: [*]const u8, count: usize) isize {
    return errno_mod.syscall_ret(
        syscall.syscall3(syscall.nr.WRITE, @intCast(fd), @intFromPtr(buf), count),
    );
}

/// Read bytes from a file descriptor.
export fn read(fd: c_int, buf: [*]u8, count: usize) isize {
    return errno_mod.syscall_ret(
        syscall.syscall3(syscall.nr.READ, @intCast(fd), @intFromPtr(buf), count),
    );
}

/// Close a file descriptor.
export fn close(fd: c_int) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall1(syscall.nr.CLOSE, @intCast(fd)),
    );
    return @intCast(ret);
}
