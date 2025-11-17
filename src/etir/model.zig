const std = @import("std");
const errors = @import("../internal/errors.zig");

pub const instructionsFromEtir = struct {
    pub fn emit(
        allocator: std.mem.Allocator,
        etir_json_path: []const u8,
        instructions_out_json_path: []const u8,
    ) errors.Result {
        _ = allocator;
        _ = etir_json_path;
        _ = instructions_out_json_path;
        return errors.failure(.INTERNAL, "instructions emitter not implemented");
    }
};
