const std = @import("std");
const common = @import("common.zig");

pub const Inputs = struct {
    stage_step: *std.Build.Step,
};

pub const Outputs = struct {
    lint_step: *std.Build.Step,
};

pub fn setup(b: *std.Build, js: common.JsConfig, inputs: Inputs) Outputs {
    var fmt_args = std.ArrayList([]const u8).empty;
    fmt_args.append(b.allocator, "zig") catch @panic("OOM");
    fmt_args.append(b.allocator, "fmt") catch @panic("OOM");
    fmt_args.append(b.allocator, ".") catch @panic("OOM");

    const optional_targets = [_][]const u8{ "tests", "examples" };
    for (optional_targets) |dir| {
        std.fs.cwd().access(dir, .{}) catch continue;
        fmt_args.append(b.allocator, dir) catch @panic("OOM");
    }

    const zig_fmt = b.addSystemCommand(fmt_args.toOwnedSlice(b.allocator) catch @panic("OOM"));

    const biome_format = common.packageManagerCommand(b, js, &.{ "run", "format" });
    biome_format.step.dependOn(inputs.stage_step);

    const biome_lint = common.packageManagerCommand(b, js, &.{ "run", "lint" });
    biome_lint.step.dependOn(inputs.stage_step);

    const lint_step = b.step("lint", "Format + lint Zig and Node sources");
    lint_step.dependOn(&zig_fmt.step);
    lint_step.dependOn(&biome_format.step);
    lint_step.dependOn(&biome_lint.step);

    return .{
        .lint_step = lint_step,
    };
}
