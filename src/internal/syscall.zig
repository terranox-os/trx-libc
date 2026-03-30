//! Syscall dispatch layer.
//!
//! Imports syscall numbers from genesis_syscall.h via @cImport
//! and provides architecture-conditional inline assembly wrappers.
//!
//! Supported architectures:
//!   - x86_64:  SYSCALL instruction (rax=nr, rdi/rsi/rdx/r10/r8/r9=args, rax=ret)
//!   - AArch64: SVC #0 instruction (x8=nr, x0-x5=args, x0=ret)
//!   - RISC-V 64: ECALL instruction (a7=nr, a0-a5=args, a0=ret)

const builtin = @import("builtin");
const arch = builtin.cpu.arch;

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
    pub const DUP2: usize = c.GEN_SYS_DUP2;
    pub const PIPE: usize = c.GEN_SYS_PIPE;

    // TerranoxOS-specific filesystem syscalls (subsystem 4)
    pub const TRX_FS_MKDIR: usize = c.GEN_SYS_TRX_FS_MKDIR;
    pub const TRX_FS_UNLINK: usize = c.GEN_SYS_TRX_FS_UNLINK;

    // Shared I/O multiplexing
    pub const POLL: usize = c.GEN_SYS_POLL;

    // TerranoxOS-specific process management (subsystem 0)
    pub const TRX_PROCESS_KILL: usize = c.GEN_SYS_TRX_PROCESS_KILL;

    // TerranoxOS-specific IPC (subsystem 3)
    pub const TRX_EVENT_WAIT_MANY: usize = c.GEN_SYS_TRX_EVENT_WAIT_MANY;

    // TerranoxOS-specific networking syscalls (subsystem 8)
    pub const TRX_NET_SOCKET: usize = c.GEN_SYS_TRX_NET_SOCKET;
    pub const TRX_NET_BIND: usize = c.GEN_SYS_TRX_NET_BIND;
    pub const TRX_NET_LISTEN: usize = c.GEN_SYS_TRX_NET_LISTEN;
    pub const TRX_NET_ACCEPT: usize = c.GEN_SYS_TRX_NET_ACCEPT;
    pub const TRX_NET_CONNECT: usize = c.GEN_SYS_TRX_NET_CONNECT;
    pub const TRX_NET_SENDMSG: usize = c.GEN_SYS_TRX_NET_SENDMSG;
    pub const TRX_NET_RECVMSG: usize = c.GEN_SYS_TRX_NET_RECVMSG;
};

pub fn syscall0(number: usize) usize {
    return switch (arch) {
        .x86_64 => asm volatile ("syscall"
            : [ret] "={rax}" (-> usize),
            : [number] "{rax}" (number),
            : "rcx", "r11", "memory"
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
            : "memory"
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
            : "memory"
        ),
        else => @compileError("unsupported architecture"),
    };
}

pub fn syscall1(number: usize, arg1: usize) usize {
    return switch (arch) {
        .x86_64 => asm volatile ("syscall"
            : [ret] "={rax}" (-> usize),
            : [number] "{rax}" (number),
              [arg1] "{rdi}" (arg1),
            : "rcx", "r11", "memory"
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
            : "memory"
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
            : "memory"
        ),
        else => @compileError("unsupported architecture"),
    };
}

pub fn syscall2(number: usize, arg1: usize, arg2: usize) usize {
    return switch (arch) {
        .x86_64 => asm volatile ("syscall"
            : [ret] "={rax}" (-> usize),
            : [number] "{rax}" (number),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
            : "rcx", "r11", "memory"
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
              [arg2] "{x1}" (arg2),
            : "memory"
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
              [arg2] "{a1}" (arg2),
            : "memory"
        ),
        else => @compileError("unsupported architecture"),
    };
}

pub fn syscall3(number: usize, arg1: usize, arg2: usize, arg3: usize) usize {
    return switch (arch) {
        .x86_64 => asm volatile ("syscall"
            : [ret] "={rax}" (-> usize),
            : [number] "{rax}" (number),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
              [arg3] "{rdx}" (arg3),
            : "rcx", "r11", "memory"
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
              [arg2] "{x1}" (arg2),
              [arg3] "{x2}" (arg3),
            : "memory"
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
              [arg2] "{a1}" (arg2),
              [arg3] "{a2}" (arg3),
            : "memory"
        ),
        else => @compileError("unsupported architecture"),
    };
}

pub fn syscall4(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize) usize {
    return switch (arch) {
        .x86_64 => asm volatile ("syscall"
            : [ret] "={rax}" (-> usize),
            : [number] "{rax}" (number),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
              [arg3] "{rdx}" (arg3),
              [arg4] "{r10}" (arg4),
            : "rcx", "r11", "memory"
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
              [arg2] "{x1}" (arg2),
              [arg3] "{x2}" (arg3),
              [arg4] "{x3}" (arg4),
            : "memory"
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
              [arg2] "{a1}" (arg2),
              [arg3] "{a2}" (arg3),
              [arg4] "{a3}" (arg4),
            : "memory"
        ),
        else => @compileError("unsupported architecture"),
    };
}

pub fn syscall5(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) usize {
    return switch (arch) {
        .x86_64 => asm volatile ("syscall"
            : [ret] "={rax}" (-> usize),
            : [number] "{rax}" (number),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
              [arg3] "{rdx}" (arg3),
              [arg4] "{r10}" (arg4),
              [arg5] "{r8}" (arg5),
            : "rcx", "r11", "memory"
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
              [arg2] "{x1}" (arg2),
              [arg3] "{x2}" (arg3),
              [arg4] "{x3}" (arg4),
              [arg5] "{x4}" (arg5),
            : "memory"
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
              [arg2] "{a1}" (arg2),
              [arg3] "{a2}" (arg3),
              [arg4] "{a3}" (arg4),
              [arg5] "{a4}" (arg5),
            : "memory"
        ),
        else => @compileError("unsupported architecture"),
    };
}

pub fn syscall6(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize) usize {
    return switch (arch) {
        .x86_64 => asm volatile ("syscall"
            : [ret] "={rax}" (-> usize),
            : [number] "{rax}" (number),
              [arg1] "{rdi}" (arg1),
              [arg2] "{rsi}" (arg2),
              [arg3] "{rdx}" (arg3),
              [arg4] "{r10}" (arg4),
              [arg5] "{r8}" (arg5),
              [arg6] "{r9}" (arg6),
            : "rcx", "r11", "memory"
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
              [arg2] "{x1}" (arg2),
              [arg3] "{x2}" (arg3),
              [arg4] "{x3}" (arg4),
              [arg5] "{x4}" (arg5),
              [arg6] "{x5}" (arg6),
            : "memory"
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
              [arg2] "{a1}" (arg2),
              [arg3] "{a2}" (arg3),
              [arg4] "{a3}" (arg4),
              [arg5] "{a4}" (arg5),
              [arg6] "{a5}" (arg6),
            : "memory"
        ),
        else => @compileError("unsupported architecture"),
    };
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
