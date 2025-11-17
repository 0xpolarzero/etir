const std = @import("std");

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    pub fn init(b: *std.Build) Options {
        return .{
            .optimize = b.standardOptimizeOption(.{}),
            .target = b.standardTargetOptions(.{}),
        };
    }
};

pub const JsConfig = struct {
    package_dir: []const u8 = "bindings/js",
    package_manager: []const u8 = "npm",
    install_args: []const []const u8 = &.{"install"},
    node_bin: []const u8 = "node",
};

pub fn packageManagerCommand(
    b: *std.Build,
    js: JsConfig,
    args: []const []const u8,
) *std.Build.Step.Run {
    var full_args = std.ArrayList([]const u8).empty;
    full_args.append(b.allocator, js.package_manager) catch @panic("OOM");
    full_args.appendSlice(b.allocator, args) catch @panic("OOM");
    const argv = full_args.toOwnedSlice(b.allocator) catch @panic("OOM");

    const cmd = b.addSystemCommand(argv);
    cmd.setCwd(b.path(js.package_dir));
    return cmd;
}
