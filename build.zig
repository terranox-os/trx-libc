const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .freestanding, .abi = .none },
        .{ .cpu_arch = .aarch64, .os_tag = .freestanding, .abi = .none },
        .{ .cpu_arch = .riscv64, .os_tag = .freestanding, .abi = .none },
    };

    for (targets) |t| {
        const resolved = b.resolveTargetQuery(t);
        const lib = b.addStaticLibrary(.{
            .name = b.fmt("c-{s}", .{@tagName(t.cpu_arch.?)}),
            .root_source_file = b.path("src/libc.zig"),
            .target = resolved,
            .optimize = optimize,
        });
        lib.root_module.red_zone = false;
        lib.root_module.stack_protector = false;
        lib.addIncludePath(b.path("deps/kernel-libs/genesis-abi/include"));
        b.installArtifact(lib);
    }

    // Install C headers for external consumers
    const install_headers = b.addInstallDirectory(.{
        .source_dir = b.path("include"),
        .install_dir = .header,
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install_headers.step);

    // Host-native tests (always native arch)
    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{
        .root_source_file = b.path("src/libc.zig"),
    });
    tests.addIncludePath(b.path("deps/kernel-libs/genesis-abi/include"));
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}
