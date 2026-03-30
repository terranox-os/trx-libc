//! Syscall dispatch layer.
//!
//! Imports syscall numbers from genesis_syscall.h via @cImport
//! and provides inline assembly wrappers for the SYSCALL instruction.

const c = @cImport({
    @cDefine("__STDC_HOSTED__", "0");
    @cInclude("genesis_syscall.h");
});

/// TerranoxOS syscall numbers imported from genesis_syscall.h.
pub const nr = struct {
    pub const EXIT: usize = c.GEN_SYS_EXIT;
    pub const WRITE: usize = c.GEN_SYS_WRITE;
    pub const READ: usize = c.GEN_SYS_READ;
    pub const OPEN: usize = c.GEN_SYS_OPEN;
    pub const CLOSE: usize = c.GEN_SYS_CLOSE;
    pub const MMAP: usize = c.GEN_SYS_MMAP;
    pub const MUNMAP: usize = c.GEN_SYS_MUNMAP;
    pub const YIELD: usize = c.GEN_SYS_YIELD;
    pub const GETPID: usize = c.GEN_SYS_GETPID;
    pub const SLEEP: usize = c.GEN_SYS_SLEEP;
    pub const LSEEK: usize = c.GEN_SYS_LSEEK;
    pub const STAT: usize = c.GEN_SYS_STAT;
    pub const FSTAT: usize = c.GEN_SYS_FSTAT;
};

pub fn syscall0(number: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (number),
        : "rcx", "r11", "memory"
    );
}

pub fn syscall1(number: usize, arg1: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
        : "rcx", "r11", "memory"
    );
}

pub fn syscall2(number: usize, arg1: usize, arg2: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
        : "rcx", "r11", "memory"
    );
}

pub fn syscall3(number: usize, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
        : "rcx", "r11", "memory"
    );
}

pub fn syscall4(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
        : "rcx", "r11", "memory"
    );
}

pub fn syscall5(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
        : "rcx", "r11", "memory"
    );
}

pub fn syscall6(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
          [arg6] "{r9}" (arg6),
        : "rcx", "r11", "memory"
    );
}

test "syscall nr constants imported from genesis_syscall.h" {
    // Verify @cImport pulled the correct values
    const testing = @import("std").testing;
    try testing.expectEqual(@as(usize, 0x0000), nr.EXIT);
    try testing.expectEqual(@as(usize, 0x0001), nr.WRITE);
    try testing.expectEqual(@as(usize, 0x0002), nr.READ);
    try testing.expectEqual(@as(usize, 0x0009), nr.OPEN);
    try testing.expectEqual(@as(usize, 0x000A), nr.CLOSE);
}
