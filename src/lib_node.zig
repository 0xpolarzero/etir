const std = @import("std");
const etir = @import("etir");

const napi = @cImport({
    @cDefine("NAPI_VERSION", "9");
    @cInclude("node_api.h");
});

fn throwTypeError(env: napi.napi_env, message: [*:0]const u8) void {
    _ = napi.napi_throw_type_error(env, null, message);
}

fn throwRangeError(env: napi.napi_env, message: [*:0]const u8) void {
    _ = napi.napi_throw_range_error(env, null, message);
}

fn napiOk(env: napi.napi_env, status: napi.napi_status) bool {
    if (status == napi.napi_ok) return true;
    _ = napi.napi_throw_error(env, null, "Unexpected N-API failure");
    return false;
}

fn etirAdd(env: napi.napi_env, info: napi.napi_callback_info) callconv(.c) napi.napi_value {
    var argc: usize = 2;
    var args: [2]napi.napi_value = undefined;
    if (!napiOk(env, napi.napi_get_cb_info(env, info, &argc, &args, null, null))) return null;
    if (argc < 2) {
        throwTypeError(env, "Expected two arguments");
        return null;
    }

    var a: i32 = 0;
    var b: i32 = 0;
    if (!napiOk(env, napi.napi_get_value_int32(env, args[0], &a))) return null;
    if (!napiOk(env, napi.napi_get_value_int32(env, args[1], &b))) return null;

    var result: napi.napi_value = null;
    if (!napiOk(env, napi.napi_create_int32(env, etir.add(a, b), &result))) return null;
    return result;
}

fn etirChecksum(env: napi.napi_env, info: napi.napi_callback_info) callconv(.c) napi.napi_value {
    var argc: usize = 1;
    var args: [1]napi.napi_value = undefined;
    if (!napiOk(env, napi.napi_get_cb_info(env, info, &argc, &args, null, null))) return null;
    if (argc < 1) {
        throwTypeError(env, "Expected a Buffer");
        return null;
    }

    var is_buffer: napi.bool = false;
    if (!napiOk(env, napi.napi_is_buffer(env, args[0], &is_buffer))) return null;
    if (!is_buffer) {
        throwTypeError(env, "Expected a Buffer");
        return null;
    }

    var data: ?*anyopaque = null;
    var length: usize = 0;
    if (!napiOk(env, napi.napi_get_buffer_info(env, args[0], &data, &length))) return null;
    if (data == null) {
        throwTypeError(env, "Invalid Buffer");
        return null;
    }

    const bytes = @as([*]u8, @ptrCast(data.?))[0..length];
    const sum = etir.checksum(bytes);

    var result: napi.napi_value = null;
    if (!napiOk(env, napi.napi_create_uint32(env, sum, &result))) return null;
    return result;
}

fn etirReduce(env: napi.napi_env, info: napi.napi_callback_info) callconv(.c) napi.napi_value {
    var argc: usize = 2;
    var args: [2]napi.napi_value = undefined;
    if (!napiOk(env, napi.napi_get_cb_info(env, info, &argc, &args, null, null))) return null;
    if (argc < 2) {
        throwTypeError(env, "Expected Buffer and tolerance");
        return null;
    }

    var is_buffer: napi.bool = false;
    if (!napiOk(env, napi.napi_is_buffer(env, args[0], &is_buffer))) return null;
    if (!is_buffer) {
        throwTypeError(env, "Expected a Buffer");
        return null;
    }

    var raw: ?*anyopaque = null;
    var length: usize = 0;
    if (!napiOk(env, napi.napi_get_buffer_info(env, args[0], &raw, &length))) return null;
    if (raw == null) {
        throwTypeError(env, "Invalid Buffer");
        return null;
    }

    if (length % @sizeOf(i32) != 0) {
        throwRangeError(env, "Buffer length must be a multiple of 4");
        return null;
    }
    var tolerance: u32 = 8;
    if (!napiOk(env, napi.napi_get_value_uint32(env, args[1], &tolerance))) return null;
    const bytes = @as([*]u8, @ptrCast(raw.?))[0..length];
    const reduced = reduceBuffer(bytes, tolerance) catch return null;
    var result: napi.napi_value = null;
    if (!napiOk(env, napi.napi_create_int32(env, reduced, &result))) return null;
    return result;
}

fn reduceBuffer(bytes: []const u8, tolerance: u32) !i32 {
    const count = bytes.len / @sizeOf(i32);
    if (count == 0) {
        return etir.reduce(&[_]i32{}, .{ .tolerance = tolerance });
    }

    const allocator = std.heap.c_allocator;
    var temp = try allocator.alloc(i32, count);
    defer allocator.free(temp);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const offset = i * @sizeOf(i32);
        temp[i] = readI32LE(bytes[offset .. offset + @sizeOf(i32)]);
    }
    return etir.reduce(temp, .{ .tolerance = tolerance });
}

fn readI32LE(chunk: []const u8) i32 {
    const value = @as(u32, chunk[0]) | (@as(u32, chunk[1]) << 8) | (@as(u32, chunk[2]) << 16) | (@as(u32, chunk[3]) << 24);
    const signed: i32 = @bitCast(value);
    return signed;
}

fn etirVersion(env: napi.napi_env, info: napi.napi_callback_info) callconv(.c) napi.napi_value {
    _ = info;
    var buf: [64]u8 = undefined;
    const written = etir.formatVersion(&buf) catch {
        _ = napi.napi_throw_error(env, null, "Failed to format version");
        return null;
    };

    var result: napi.napi_value = null;
    if (!napiOk(env, napi.napi_create_string_utf8(env, written.ptr, written.len, &result))) return null;
    return result;
}

fn defineFunction(env: napi.napi_env, exports: napi.napi_value, comptime name: []const u8, callback: napi.napi_callback) bool {
    var fn_value: napi.napi_value = null;
    if (!napiOk(env, napi.napi_create_function(env, name.ptr, name.len, callback, null, &fn_value))) return false;
    if (!napiOk(env, napi.napi_set_named_property(env, exports, name.ptr, fn_value))) return false;
    return true;
}

export fn napi_register_module_v1(env: napi.napi_env, exports: napi.napi_value) callconv(.c) napi.napi_value {
    if (!defineFunction(env, exports, "etir_add", etirAdd)) return null;
    if (!defineFunction(env, exports, "etir_checksum", etirChecksum)) return null;
    if (!defineFunction(env, exports, "etir_reduce", etirReduce)) return null;
    if (!defineFunction(env, exports, "etir_version", etirVersion)) return null;
    return exports;
}
