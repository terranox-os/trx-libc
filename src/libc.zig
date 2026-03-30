//! TerranoxOS POSIX C Library (trx-libc)
//!
//! Custom POSIX.1-2017 implementation targeting the TerranoxOS 91-syscall ABI.
//! Implemented in Zig, exports C ABI symbols via `export fn`.

pub const syscall = @import("internal/syscall.zig");
pub const errno_mod = @import("errno/errno.zig");
pub const crt = @import("crt/crt.zig");

// POSIX function exports
pub const unistd = @import("unistd/unistd.zig");
pub const misc = @import("misc/misc.zig");
pub const string = @import("string/string.zig");
pub const stdlib = @import("stdlib/stdlib.zig");
pub const ctype = @import("ctype/ctype.zig");

// Re-export for tests
test {
    _ = syscall;
    _ = errno_mod;
    _ = unistd;
    _ = misc;
    _ = string;
    _ = stdlib;
    _ = ctype;
}
