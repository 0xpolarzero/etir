const std = @import("std");
const errors = @import("../internal/errors.zig");

pub const RunOptions = struct {
    base: []const u8,
    etir: []const u8,
    out: []const u8,
    strict: bool,
};

pub fn run(allocator: std.mem.Allocator, options: RunOptions) errors.Result {
    _ = allocator;
    _ = options;
    return errors.failure(.INTERNAL, "fromEtir pipeline not implemented");
}
