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
    _ = opts;
    const host_tests = b.addTest(.{ .root_module = inputs.lib_module });
    const run_host_tests = b.addRunArtifact(host_tests);

    const js_tests = common.packageManagerCommand(b, js, &.{ "run", "test" });
    js_tests.step.dependOn(inputs.stage_step);

    const test_step = b.step("test", "Run Zig unit tests and Node bindings tests");
    test_step.dependOn(&run_host_tests.step);
    test_step.dependOn(&js_tests.step);

    return .{ .step = test_step };
}
