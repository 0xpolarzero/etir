const std = @import("std");
const common = @import("common.zig");
const node_build = @import("node.zig");
const js_build = @import("js.zig");

pub const Inputs = struct {
    node: node_build.Outputs,
};

pub const Outputs = struct {
    stage: *std.Build.Step.Run,
    install: *std.Build.Step.Run,
    step: *std.Build.Step,
};

pub fn setup(b: *std.Build, opts: common.Options, js: common.JsConfig, inputs: Inputs) Outputs {
    const addon_install_dir: std.Build.InstallDir = if (opts.target.result.os.tag == .windows) .bin else .lib;
    const addon_path = b.getInstallPath(addon_install_dir, "node/etir.node");
    const js_outputs = js_build.setup(b, js, .{
        .native_step = &inputs.node.install.step,
        .native_path = addon_path,
    });

    const pkg_step = b.step("package", "Build Node addon + JS package");
    pkg_step.dependOn(js_outputs.step);

    return .{ .stage = js_outputs.stage, .install = js_outputs.install, .step = pkg_step };
}
