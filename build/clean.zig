const std = @import("std");
const common = @import("common.zig");

pub fn setup(b: *std.Build, js: common.JsConfig) *std.Build.Step {
    const rm_zig_cache = b.addRemoveDirTree(b.path(".zig-cache"));
    const rm_zig_out = b.addRemoveDirTree(b.path("zig-out"));

    const js_clean = common.packageManagerCommand(b, js, &.{ "run", "clean" });

    const clean_step = b.step("clean", "Remove build artifacts and JS bindings outputs");
    clean_step.dependOn(&rm_zig_cache.step);
    clean_step.dependOn(&rm_zig_out.step);
    clean_step.dependOn(&js_clean.step);

    return clean_step;
}
