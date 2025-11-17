const std = @import("std");
const common = @import("common.zig");

pub const Inputs = struct {
    lib_module: *std.Build.Module,
    stage_step: *std.Build.Step,
};

pub const Outputs = struct {
    step: *std.Build.Step,
};

pub fn setup(b: *std.Build, opts: common.Options, js: common.JsConfig, inputs: Inputs) Outputs {
    const repo_root_opts = b.addOptions();
    repo_root_opts.addOptionPath("repo_root", b.path("."));

    const host_tests = b.addTest(.{ .root_module = inputs.lib_module });
    const run_host_tests = b.addRunArtifact(host_tests);
    run_host_tests.cwd = b.path(".");

    const e2e_files = [_][]const u8{
        "tests/e2e/corpus_sanity.zig",
        "tests/e2e/schema_sanity.zig",
        "tests/e2e/pipeline_placeholder.zig",
    };

    var e2e_runs: [e2e_files.len]*std.Build.Step.Run = undefined;
    for (e2e_files, 0..) |path, idx| {
        const module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = opts.target,
            .optimize = opts.optimize,
        });
        module.addImport("etir", inputs.lib_module);
        module.addOptions("build_options", repo_root_opts);
        const exe = b.addTest(.{ .root_module = module });
        e2e_runs[idx] = b.addRunArtifact(exe);
        e2e_runs[idx].cwd = b.path(".");
    }

    const js_tests = common.packageManagerCommand(b, js, &.{ "run", "test" });
    js_tests.step.dependOn(inputs.stage_step);

    const test_step = b.step("test", "Run Zig unit tests and Node bindings tests");
    test_step.dependOn(&run_host_tests.step);
    for (e2e_runs) |run_step| {
        test_step.dependOn(&run_step.step);
    }
    test_step.dependOn(&js_tests.step);

    return .{ .step = test_step };
}
