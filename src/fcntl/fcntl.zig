//! POSIX fcntl.h function implementations.

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

// O_* flag constants (POSIX / TerranoxOS ABI)
pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_RDWR: c_int = 2;
pub const O_CREAT: c_int = 0o100;
pub const O_EXCL: c_int = 0o200;
pub const O_TRUNC: c_int = 0o1000;
pub const O_APPEND: c_int = 0o2000;

/// Open a file.
///
/// Exported as a 3-arg function (path, flags, mode). The C header declares
/// open() as variadic — the ABI is compatible because extra args on the
/// stack/registers are simply ignored by the kernel when O_CREAT is not set.
export fn open(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall3(
            syscall.nr.OPEN,
            @intFromPtr(path),
            @intCast(flags),
            @as(usize, mode),
        ),
    );
    return @intCast(ret);
}
