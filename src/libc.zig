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
pub const fcntl = @import("fcntl/fcntl.zig");
pub const sys_stat = @import("sys/stat.zig");
pub const stdio = @import("stdio/stdio.zig");
pub const malloc_mod = @import("malloc/malloc.zig");
pub const pthread = @import("pthread/pthread.zig");
pub const net = @import("net/net.zig");
pub const poll = @import("poll/poll.zig");

// Phase 5: Signal handling
pub const signal_mod = @import("signal/signal.zig");

// Phase 6: TerranoxOS extensions
pub const trx_capability = @import("terranox/capability.zig");
pub const trx_display = @import("terranox/display.zig");
pub const trx_input = @import("terranox/input.zig");
pub const trx_gpu = @import("terranox/gpu.zig");
pub const trx_ipc = @import("terranox/ipc.zig");

// Re-export for tests
test {
    _ = syscall;
    _ = errno_mod;
    _ = unistd;
    _ = misc;
    _ = string;
    _ = stdlib;
    _ = ctype;
    _ = fcntl;
    _ = sys_stat;
    _ = stdio;
    _ = malloc_mod;
    _ = pthread;
    _ = net;
    _ = poll;
    _ = signal_mod;
    _ = trx_capability;
    _ = trx_display;
    _ = trx_input;
    _ = trx_gpu;
    _ = trx_ipc;
}
