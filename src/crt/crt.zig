//! C runtime startup (crt0).
//!
//! Provides _start (process entry point) and __libc_start_main.
//! The kernel places argc, argv, envp on the stack before jumping to _start.
//!
//! Architecture-conditional: supports x86_64, AArch64, and RISC-V 64.

const builtin = @import("builtin");
const arch = builtin.cpu.arch;
const is_test = builtin.is_test;

const misc = @import("../misc/misc.zig");

// CRT entry points are only exported in freestanding builds.
// In test mode, the Zig test runner provides its own _start.
comptime {
    if (!is_test) {
        @export(&__libc_start_main_impl, .{ .name = "__libc_start_main", .linkage = .strong });
        @export(&_start_impl, .{ .name = "_start", .linkage = .strong });
    }
}

/// External main function provided by the user program.
extern fn main(argc: c_int, argv: [*]const [*:0]const u8) c_int;

/// C runtime entry point. Called by _start after stack alignment.
pub fn __libc_start_main_impl(stack_ptr: [*]const usize) callconv(.c) noreturn {
    // Stack layout (System V ABI):
    //   [rsp+0]  = argc
    //   [rsp+8]  = argv[0]
    //   ...
    //   [rsp+8*(argc+1)] = NULL
    //   [rsp+8*(argc+2)] = envp[0]
    //   ...
    const argc: c_int = @intCast(stack_ptr[0]);
    const argv: [*]const [*:0]const u8 = @ptrCast(stack_ptr + 1);

    const ret = main(argc, argv);
    misc._exit(ret);
}

/// Process entry point (naked -- no prologue).
/// Aligns the stack to 16 bytes and calls __libc_start_main.
pub fn _start_impl() callconv(.naked) noreturn {
    // Zero frame pointer (marks outermost frame for debuggers)
    // Pass stack pointer as argument to __libc_start_main
    // Align stack to 16 bytes (ABI requirement)
    asm volatile (switch (arch) {
        .x86_64 =>
            \\xorl %%ebp, %%ebp
            \\movq %%rsp, %%rdi
            \\andq $-16, %%rsp
            \\callq %[__libc_start_main:P]
            \\ud2
            ,
        .aarch64 =>
            \\mov x29, #0
            \\mov x0, sp
            \\and sp, x0, #-16
            \\b %[__libc_start_main]
            ,
        .riscv64 =>
            \\li fp, 0
            \\mv a0, sp
            \\andi sp, sp, -16
            \\tail %[__libc_start_main]
            ,
        else => @compileError("unsupported architecture"),
    }
        :
        : [__libc_start_main] "X" (&__libc_start_main_impl),
    );
}
