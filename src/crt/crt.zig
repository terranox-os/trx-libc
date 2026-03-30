//! C runtime startup (crt0).
//!
//! Provides _start (process entry point) and __libc_start_main.
//! The kernel places argc, argv, envp on the stack before jumping to _start.

const misc = @import("../misc/misc.zig");

/// External main function provided by the user program.
extern fn main(argc: c_int, argv: [*]const [*:0]const u8) c_int;

/// C runtime entry point. Called by _start after stack alignment.
export fn __libc_start_main(stack_ptr: [*]const usize) noreturn {
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
export fn _start() callconv(.Naked) noreturn {
    // Zero frame pointer (marks outermost frame for debuggers)
    // Pass stack pointer as argument to __libc_start_main
    // Align stack to 16 bytes (ABI requirement)
    asm volatile (
        \\xorl %%ebp, %%ebp
        \\movq %%rsp, %%rdi
        \\andq $-16, %%rsp
        \\call __libc_start_main
        \\ud2
    );
    unreachable;
}
