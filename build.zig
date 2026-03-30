const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "c",
        .root_source_file = b.path("src/libc.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.red_zone = false;
    lib.root_module.stack_protector = false;

    // kernel-libs headers for @cImport
    lib.addIncludePath(b.path("deps/kernel-libs/genesis-abi/include"));

    b.installArtifact(lib);

    // Host-native tests
    const test_step = b.step("test", "Run unit tests");
    const tests = b.addTest(.{
        .root_source_file = b.path("src/libc.zig"),
    });
    tests.addIncludePath(b.path("deps/kernel-libs/genesis-abi/include"));
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}
