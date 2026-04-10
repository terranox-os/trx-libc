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

    // TerranoxOS-specific thread management (subsystem 1)
    pub const TRX_THREAD_CREATE: usize = c.GEN_SYS_TRX_THREAD_CREATE;
    pub const TRX_THREAD_EXIT: usize = c.GEN_SYS_TRX_THREAD_EXIT;
    pub const TRX_THREAD_JOIN: usize = c.GEN_SYS_TRX_THREAD_JOIN;
    pub const TRX_FUTEX_WAIT: usize = c.GEN_SYS_TRX_FUTEX_WAIT;
    pub const TRX_FUTEX_WAKE: usize = c.GEN_SYS_TRX_FUTEX_WAKE;

    // TerranoxOS-specific process management (subsystem 0)
    pub const TRX_PROCESS_CAP_GRANT: usize = c.GEN_SYS_TRX_PROCESS_CAP_GRANT;
    pub const TRX_PROCESS_CAP_REVOKE: usize = c.GEN_SYS_TRX_PROCESS_CAP_REVOKE;
    pub const TRX_PROCESS_CAP_QUERY: usize = c.GEN_SYS_TRX_PROCESS_CAP_QUERY;

    // TerranoxOS-specific IPC (subsystem 3)
    pub const TRX_CHANNEL_CREATE: usize = c.GEN_SYS_TRX_CHANNEL_CREATE;
    pub const TRX_CHANNEL_SEND: usize = c.GEN_SYS_TRX_CHANNEL_SEND;
    pub const TRX_CHANNEL_RECV: usize = c.GEN_SYS_TRX_CHANNEL_RECV;
    pub const TRX_CHANNEL_CLOSE: usize = c.GEN_SYS_TRX_CHANNEL_CLOSE;
    pub const TRX_SIGNAL_CREATE: usize = c.GEN_SYS_TRX_SIGNAL_CREATE;
    pub const TRX_SIGNAL_RAISE: usize = c.GEN_SYS_TRX_SIGNAL_RAISE;
    pub const TRX_SIGNAL_WAIT: usize = c.GEN_SYS_TRX_SIGNAL_WAIT;

    // TerranoxOS-specific display/compositor (subsystem 5)
    pub const TRX_DISPLAY_ENUMERATE: usize = c.GEN_SYS_TRX_DISPLAY_ENUMERATE;
    pub const TRX_DISPLAY_SET_MODE: usize = c.GEN_SYS_TRX_DISPLAY_SET_MODE;
    pub const TRX_COMPOSITOR_CREATE: usize = c.GEN_SYS_TRX_COMPOSITOR_CREATE;
    pub const TRX_COMPOSITOR_PRESENT: usize = c.GEN_SYS_TRX_COMPOSITOR_PRESENT;
    pub const TRX_SURFACE_CREATE: usize = c.GEN_SYS_TRX_SURFACE_CREATE;
    pub const TRX_SURFACE_DESTROY: usize = c.GEN_SYS_TRX_SURFACE_DESTROY;
    pub const TRX_BUFFER_CREATE: usize = c.GEN_SYS_TRX_BUFFER_CREATE;
    pub const TRX_BUFFER_MAP: usize = c.GEN_SYS_TRX_BUFFER_MAP;
    pub const TRX_BUFFER_UNMAP: usize = c.GEN_SYS_TRX_BUFFER_UNMAP;

    // TerranoxOS-specific input devices (subsystem 6)
    pub const TRX_INPUT_ENUMERATE: usize = c.GEN_SYS_TRX_INPUT_ENUMERATE;
    pub const TRX_INPUT_OPEN: usize = c.GEN_SYS_TRX_INPUT_OPEN;
    pub const TRX_INPUT_CLOSE: usize = c.GEN_SYS_TRX_INPUT_CLOSE;
    pub const TRX_INPUT_READ_EVENTS: usize = c.GEN_SYS_TRX_INPUT_READ_EVENTS;
    pub const TRX_INPUT_GRAB: usize = c.GEN_SYS_TRX_INPUT_GRAB;
    pub const TRX_INPUT_UNGRAB: usize = c.GEN_SYS_TRX_INPUT_UNGRAB;

    // TerranoxOS-specific GPU/DRM (subsystem 7)
    pub const TRX_GPU_OPEN: usize = c.GEN_SYS_TRX_GPU_OPEN;
    pub const TRX_GPU_CLOSE: usize = c.GEN_SYS_TRX_GPU_CLOSE;
    pub const TRX_GPU_ALLOC_BO: usize = c.GEN_SYS_TRX_GPU_ALLOC_BO;
    pub const TRX_GPU_FREE_BO: usize = c.GEN_SYS_TRX_GPU_FREE_BO;
    pub const TRX_GPU_SUBMIT: usize = c.GEN_SYS_TRX_GPU_SUBMIT;
    pub const TRX_GPU_WAIT_FENCE: usize = c.GEN_SYS_TRX_GPU_WAIT_FENCE;

    // TerranoxOS-specific networking (subsystem 8)
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
            : .{ .rcx = true, .r11 = true, .memory = true }
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
            : .{ .memory = true }
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
            : .{ .memory = true }
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
            : .{ .rcx = true, .r11 = true, .memory = true }
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
            : .{ .memory = true }
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
            : .{ .memory = true }
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
            : .{ .rcx = true, .r11 = true, .memory = true }
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
              [arg2] "{x1}" (arg2),
            : .{ .memory = true }
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
              [arg2] "{a1}" (arg2),
            : .{ .memory = true }
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
            : .{ .rcx = true, .r11 = true, .memory = true }
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
              [arg2] "{x1}" (arg2),
              [arg3] "{x2}" (arg3),
            : .{ .memory = true }
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
              [arg2] "{a1}" (arg2),
              [arg3] "{a2}" (arg3),
            : .{ .memory = true }
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
            : .{ .rcx = true, .r11 = true, .memory = true }
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
              [arg2] "{x1}" (arg2),
              [arg3] "{x2}" (arg3),
              [arg4] "{x3}" (arg4),
            : .{ .memory = true }
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
              [arg2] "{a1}" (arg2),
              [arg3] "{a2}" (arg3),
              [arg4] "{a3}" (arg4),
            : .{ .memory = true }
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
            : .{ .rcx = true, .r11 = true, .memory = true }
        ),
        .aarch64 => asm volatile ("svc #0"
            : [ret] "={x0}" (-> usize),
            : [number] "{x8}" (number),
              [arg1] "{x0}" (arg1),
              [arg2] "{x1}" (arg2),
              [arg3] "{x2}" (arg3),
              [arg4] "{x3}" (arg4),
              [arg5] "{x4}" (arg5),
            : .{ .memory = true }
        ),
        .riscv64 => asm volatile ("ecall"
            : [ret] "={a0}" (-> usize),
            : [number] "{a7}" (number),
              [arg1] "{a0}" (arg1),
              [arg2] "{a1}" (arg2),
              [arg3] "{a2}" (arg3),
              [arg4] "{a3}" (arg4),
              [arg5] "{a4}" (arg5),
            : .{ .memory = true }
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
            : .{ .rcx = true, .r11 = true, .memory = true }
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
            : .{ .memory = true }
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
            : .{ .memory = true }
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
