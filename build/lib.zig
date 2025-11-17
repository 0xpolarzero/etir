const std = @import("std");
const common = @import("common.zig");

pub const Outputs = struct {
    module: *std.Build.Module,
    static_artifact: *std.Build.Step.Compile,
    shared_artifact: *std.Build.Step.Compile,
    step: *std.Build.Step,
};

pub fn setup(b: *std.Build, opts: common.Options) Outputs {
    const core_module = b.addModule("etir", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    const c_module = b.createModule(.{
        .root_source_file = b.path("src/lib_c.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    const static_lib = b.addLibrary(.{
        .name = "etir",
        .root_module = c_module,
        .linkage = .static,
        .version = null,
    });
    b.installArtifact(static_lib);

    const shared_lib = b.addLibrary(.{
        .name = "etir",
        .root_module = c_module,
        .linkage = .dynamic,
        .version = null,
    });
    b.installArtifact(shared_lib);

    const lib_step = b.step("lib", "Build and install the etir native libraries");
    lib_step.dependOn(&static_lib.step);
    lib_step.dependOn(&shared_lib.step);

    return .{
        .module = core_module,
        .static_artifact = static_lib,
        .shared_artifact = shared_lib,
        .step = lib_step,
    };
}
