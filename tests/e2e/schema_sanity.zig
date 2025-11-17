const std = @import("std");
const json = std.json;

const schema_paths = [_][]const u8{
    "schema/etir.schema.json",
    "schema/sourcemap.schema.json",
    "schema/instructions.schema.json",
};

test "JSON Schemas expose required headers" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for (schema_paths) |path| {
        const data = try std.fs.cwd().readFileAlloc(allocator, path, 1 << 20);
        defer allocator.free(data);
        var parsed = try json.parseFromSlice(json.Value, allocator, data, .{});
        defer parsed.deinit();
        const obj = switch (parsed.value) {
            .object => |o| o,
            else => return error.SchemaNotObject,
        };
        const schema_uri = try requireString(obj, "$schema", error.SchemaMissing, error.SchemaWrongType);
        const schema_id = try requireString(obj, "$id", error.SchemaMissingId, error.SchemaWrongType);
        const title = try requireString(obj, "title", error.SchemaMissingTitle, error.SchemaWrongType);
        try std.testing.expect(schema_uri.len > 0);
        try std.testing.expect(schema_id.len > 0);
        try std.testing.expect(title.len > 0);
    }
}

fn requireString(
    obj: json.ObjectMap,
    key: []const u8,
    missing_err: anyerror,
    type_err: anyerror,
) ![]const u8 {
    const value = obj.get(key) orelse return missing_err;
    return switch (value) {
        .string => |s| s,
        else => type_err,
    };
}
