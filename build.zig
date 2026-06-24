const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const aro = b.dependency("aro", .{
        .target = target,
        .optimize = optimize,
    });

    // for default system includes
    b.installDirectory(.{
        .source_dir = aro.path("include"),
        .install_dir = .prefix,
        .install_subdir = "include",
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "aro", .module = aro.module("aro") },
        },
    });

    // current nightly version loops forever on self-hosted backend for arm mac
    // so we default to llvm backend in that case
    const use_llvm = b.option(bool, "llvm", "compile with LLVM") orelse
        (target.result.cpu.arch == .aarch64 and target.result.os.tag == .macos);
    const exe = b.addExecutable(.{
        .name = "header-gen",
        .root_module = mod,
        .use_llvm = use_llvm,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPassthruArgs();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "run executable");
    run_step.dependOn(&run_cmd.step);

    // tests
    const filters = b.option([]const []const u8, "testfilter", "test filters to run") orelse &.{};
    const test_exe = b.addTest(.{
        .root_module = mod,
        .filters = filters,
    });
    const run_tests_cmd = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "test app");
    test_step.dependOn(&run_tests_cmd.step);

    // check
    const check_exe = b.addExecutable(.{
        .name = "check",
        .root_module = mod,
        .use_llvm = use_llvm,
    });

    const check_step = b.step("check", "check app compiles");
    check_step.dependOn(&check_exe.step);
    check_step.dependOn(&test_exe.step);
}
