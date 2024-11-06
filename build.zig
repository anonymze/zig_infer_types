const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-infer-types",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // const simargs_dep = b.dependency("simargs", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // exe.addModule("simargs", simargs_dep.module("simargs"));
    b.installArtifact(exe);
}
