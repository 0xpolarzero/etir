const std = @import("std");
const errors = @import("../internal/errors.zig");

pub fn run(
    allocator: std.mem.Allocator,
    docx_path: []const u8,
    etir_out_json_path: []const u8,
    map_out_json_path: []const u8,
) errors.Result {
    _ = allocator;
    _ = docx_path;
    _ = etir_out_json_path;
    _ = map_out_json_path;
    return errors.failure(.INTERNAL, "toEtir pipeline not implemented");
}
