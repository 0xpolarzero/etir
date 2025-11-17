const std = @import("std");
const common = @import("common.zig");

pub const Inputs = struct {
    native_step: *std.Build.Step,
    native_path: []const u8,
};

pub const Outputs = struct {
    install: *std.Build.Step.Run,
    typecheck: *std.Build.Step.Run,
    build: *std.Build.Step.Run,
    stage: *std.Build.Step.Run,
    step: *std.Build.Step,
};

pub fn setup(b: *std.Build, js: common.JsConfig, inputs: Inputs) Outputs {
    const install_cmd = common.packageManagerCommand(b, js, js.install_args);
    const stage_cmd = b.addSystemCommand(&.{js.node_bin});
    stage_cmd.step.dependOn(&install_cmd.step);
    stage_cmd.step.dependOn(inputs.native_step);
    const script_path = b.path("bindings/js/scripts/stage-native.mjs");
    const dest_path = b.path("bindings/js/dist/native");
    stage_cmd.addArg(script_path.getPath2(b, &stage_cmd.step));
    stage_cmd.addArg("--source");
    stage_cmd.addArg(inputs.native_path);
    stage_cmd.addArg("--dest");
    stage_cmd.addArg(dest_path.getPath2(b, &stage_cmd.step));

    const typecheck = common.packageManagerCommand(b, js, &.{ "run", "typecheck" });
    typecheck.step.dependOn(&stage_cmd.step);

    const build_cmd = common.packageManagerCommand(b, js, &.{ "run", "build" });
    build_cmd.step.dependOn(&stage_cmd.step);

    const js_step = b.step("js", "Build the Node bindings");
    js_step.dependOn(&typecheck.step);
    js_step.dependOn(&build_cmd.step);

    return .{
        .install = install_cmd,
        .typecheck = typecheck,
        .build = build_cmd,
        .stage = stage_cmd,
        .step = js_step,
    };
}
