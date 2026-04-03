//! POSIX sys/stat.h function implementations.

const syscall = @import("../internal/syscall.zig");
const errno_mod = @import("../errno/errno.zig");

/// Minimal stat structure matching the TerranoxOS ABI.
pub const Stat = extern struct {
    dev: u64,
    ino: u64,
    mode: u32,
    nlink: u32,
    uid: u32,
    gid: u32,
    rdev: u64,
    size: i64,
    blksize: i64,
    blocks: i64,
    atime_sec: i64,
    atime_nsec: i64,
    mtime_sec: i64,
    mtime_nsec: i64,
    ctime_sec: i64,
    ctime_nsec: i64,
};

// S_* file mode constants
pub const S_IRWXU: c_uint = 0o700;
pub const S_IRUSR: c_uint = 0o400;
pub const S_IWUSR: c_uint = 0o200;
pub const S_IXUSR: c_uint = 0o100;
pub const S_IRWXG: c_uint = 0o070;
pub const S_IRGRP: c_uint = 0o040;
pub const S_IWGRP: c_uint = 0o020;
pub const S_IXGRP: c_uint = 0o010;
pub const S_IRWXO: c_uint = 0o007;
pub const S_IROTH: c_uint = 0o004;
pub const S_IWOTH: c_uint = 0o002;
pub const S_IXOTH: c_uint = 0o001;
pub const S_ISUID: c_uint = 0o4000;
pub const S_ISGID: c_uint = 0o2000;
pub const S_ISVTX: c_uint = 0o1000;

// File type bits
pub const S_IFMT: c_uint = 0o170000;
pub const S_IFREG: c_uint = 0o100000;
pub const S_IFDIR: c_uint = 0o040000;
pub const S_IFCHR: c_uint = 0o020000;
pub const S_IFBLK: c_uint = 0o060000;
pub const S_IFIFO: c_uint = 0o010000;
pub const S_IFLNK: c_uint = 0o120000;
pub const S_IFSOCK: c_uint = 0o140000;

/// Get file status by path.
pub export fn stat(path: [*:0]const u8, buf: *Stat) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(syscall.nr.STAT, @intFromPtr(path), @intFromPtr(buf)),
    );
    return @intCast(ret);
}

/// Get file status by file descriptor.
pub export fn fstat(fd: c_int, buf: *Stat) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(syscall.nr.FSTAT, @intCast(fd), @intFromPtr(buf)),
    );
    return @intCast(ret);
}

/// Create a directory.
pub export fn mkdir(path: [*:0]const u8, mode: c_uint) c_int {
    const ret = errno_mod.syscall_ret(
        syscall.syscall2(syscall.nr.TRX_FS_MKDIR, @intFromPtr(path), @as(usize, mode)),
    );
    return @intCast(ret);
}
