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
        const mod = b.createModule(.{
            .root_source_file = b.path("src/libc.zig"),
            .target = resolved,
            .optimize = optimize,
            .red_zone = false,
            .stack_protector = false,
            .stack_check = false,
        });
        mod.addIncludePath(b.path("deps/kernel-libs/genesis-abi/include"));
        const lib = b.addLibrary(.{
            .name = b.fmt("c-{s}", .{@tagName(t.cpu_arch.?)}),
            .root_module = mod,
        });
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
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/libc.zig"),
        .target = b.graph.host,
    });
    test_mod.addIncludePath(b.path("deps/kernel-libs/genesis-abi/include"));
    const tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}
