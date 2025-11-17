const std = @import("std");
const common = @import("build/common.zig");
const lib_build = @import("build/lib.zig");
const node_build = @import("build/node.zig");
const comparer_build = @import("build/comparer.zig");
const test_build = @import("build/test.zig");
const package_build = @import("build/package.zig");
const lint_build = @import("build/lint.zig");
const clean_build = @import("build/clean.zig");

pub fn build(b: *std.Build) void {
    const options = common.Options.init(b);
    const js_config = common.JsConfig{};

    const comparer_outputs = comparer_build.setup(b, options);
    const lib_outputs = lib_build.setup(b, options);
    const node_outputs = node_build.setup(b, options, .{ .lib_module = lib_outputs.module });
    const package_outputs = package_build.setup(b, options, js_config, .{
        .node = node_outputs,
    });
    const test_outputs = test_build.setup(b, options, js_config, .{
        .lib_module = lib_outputs.module,
        .stage_step = &package_outputs.stage.step,
    });
    test_outputs.step.dependOn(comparer_outputs.step);
    const lint_outputs = lint_build.setup(b, js_config, .{ .install_step = &package_outputs.install.step });
    _ = clean_build.setup(b, js_config);

    const all_step = b.step("all", "Run build, package, lint, and test steps");
    all_step.dependOn(comparer_outputs.step);
    all_step.dependOn(lib_outputs.step);
    all_step.dependOn(node_outputs.step);
    all_step.dependOn(package_outputs.step);
    all_step.dependOn(lint_outputs.lint_step);
    all_step.dependOn(test_outputs.step);
}
