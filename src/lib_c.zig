const std = @import("std");
const errors = @import("internal/errors.zig");
const last = @import("internal/last_error.zig");
const compare_mod = @import("comparer/compare.zig");
const to = @import("etir/to_etir.zig");
const from = @import("etir/from_etir.zig");
const instr = @import("etir/model.zig").instructionsFromEtir;

fn ok() c_int {
    return 0;
}

fn fail(code: errors.Code, msg: []const u8) c_int {
    const text = if (msg.len == 0) errors.message(code) else msg;
    last.set(text);
    return @intFromEnum(code);
}

fn handleResult(result: errors.Result) c_int {
    return switch (result) {
        .ok => ok(),
        .err => |err_state| fail(err_state.code, err_state.msg),
    };
}

pub export fn etir_docx_to_etir(
    docx_path: [*:0]const u8,
    etir_out_json_path: [*:0]const u8,
    map_out_json_path: [*:0]const u8,
) callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const res = to.run(
        allocator,
        std.mem.span(docx_path),
        std.mem.span(etir_out_json_path),
        std.mem.span(map_out_json_path),
    );
    return handleResult(res);
}

pub export fn etir_docx_from_etir(
    base_docx_path: [*:0]const u8,
    etir_json_path: [*:0]const u8,
    after_docx_out_path: [*:0]const u8,
    strict_anchors: bool,
) callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const res = from.run(allocator, .{
        .base = std.mem.span(base_docx_path),
        .etir = std.mem.span(etir_json_path),
        .out = std.mem.span(after_docx_out_path),
        .strict = strict_anchors,
    });
    return handleResult(res);
}

pub export fn etir_docx_compare(
    before_docx_path: [*:0]const u8,
    after_docx_path: [*:0]const u8,
    review_docx_out_path: [*:0]const u8,
    author_utf8: [*:0]const u8,
    date_iso_utc_or_null: ?[*:0]const u8,
) callconv(.c) c_int {
    const res = compare_mod.run(
        std.mem.span(before_docx_path),
        std.mem.span(after_docx_path),
        std.mem.span(review_docx_out_path),
        std.mem.span(author_utf8),
        if (date_iso_utc_or_null) |ptr| std.mem.span(ptr) else null,
    );
    return handleResult(res);
}

pub export fn etir_docx_get_instructions(
    etir_json_path: [*:0]const u8,
    instructions_out_json_path: [*:0]const u8,
) callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const res = instr.emit(
        allocator,
        std.mem.span(etir_json_path),
        std.mem.span(instructions_out_json_path),
    );
    return handleResult(res);
}

pub export fn etir_docx_last_error() [*:0]const u8 {
    return last.get();
}
