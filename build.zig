const std = @import("std");
const Scanner = @import("zig-wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner_exe = b.dependency("zig-wayland", .{}).artifact("zig-wayland-scanner");
    const scanner_run = b.addRunArtifact(scanner_exe);

    const scanner = Scanner.create(b, scanner_run, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");

    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_shm", 1);
    scanner.generate("xdg_wm_base", 6);
    scanner.generate("wl_seat", 8);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    const exe = b.addExecutable(.{
        .name = "zeichnung",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("wayland", wayland);
    exe.linkSystemLibrary("wayland-egl");
    exe.linkSystemLibrary("EGL");
    // exe.linkSystemLibrary("GL");
    exe.addIncludePath(b.path("glad/include"));
    exe.addIncludePath(b.path("."));
    exe.addCSourceFile(.{ .file = b.path("glad/src/gl.c") });
    exe.linkLibC();

    b.installArtifact(exe);

    scanner.addCSource(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
