const std = @import("std");

// RoofVT: a C-ABI static library over Ghostty's ghostty-vt module (T14 §3b). roofd keeps one per session.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/roofvt.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    var gvt: ?*std.Build.Module = null;
    if (b.lazyDependency("ghostty", .{})) |dep| {
        gvt = dep.module("ghostty-vt");
        mod.addImport("ghostty-vt", gvt.?);
    }

    const lib = b.addLibrary(.{ .name = "roofvt", .root_module = mod, .linkage = .static });
    lib.bundle_compiler_rt = true;
    b.installArtifact(lib);
    // A static library does not carry its dependencies: install the C/C++ libraries ghostty-vt links (simdutf,
    // highway, utfcpp) so build-roofvt.sh can merge them into one archive.
    if (gvt) |m| for (m.link_objects.items) |lo| switch (lo) {
        .other_step => |cs| b.installArtifact(cs),
        else => {},
    };
    b.installFile("include/RoofVT.h", "include/RoofVT.h");

    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Run RoofVT tests").dependOn(&b.addRunArtifact(tests).step);
}
