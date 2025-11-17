const std = @import("std");
const builtin = @import("builtin");
const errors = @import("../internal/errors.zig");

const DocxCompareFn = fn (
    before_path: [*:0]const u8,
    after_path: [*:0]const u8,
    out_path: [*:0]const u8,
    author: [*:0]const u8,
    date_iso: ?[*:0]const u8,
) callconv(.c) c_int;

const comparer_project_path = "src/comparer/dotnet/EtirComparer.csproj";
const compare_symbol = "docx_compare";
const CompareError = error{ DotnetNotFound, PublishFailed, SymbolMissing, UnsupportedTarget };

var override_compare_fn: ?*const DocxCompareFn = if (builtin.is_test) mockDocxCompare else null;
var native_dynlib: ?std.DynLib = null;
var native_compare_fn: ?*const DocxCompareFn = null;
var comparer_path_cache: ?[]const u8 = null;
threadlocal var test_compare_return: c_int = 0;

/// Runs the NativeAOT compare engine and maps failures to errors.Code values.
pub fn run(
    before_path: []const u8,
    after_path: []const u8,
    out_path: []const u8,
    author: []const u8,
    date_iso: ?[]const u8,
) errors.Result {
    if (!fileExists(before_path))
        return errors.failure(.OPEN_FAILED_BEFORE, "before docx not found");
    if (!fileExists(after_path))
        return errors.failure(.OPEN_FAILED_AFTER, "after docx not found");

    const compare_fn = resolveCompareFn() catch {
        return errors.failure(.COMPARE_FAILED, "docx comparer unavailable");
    };

    const rc = compare_fn(
        toZ(before_path),
        toZ(after_path),
        toZ(out_path),
        toZ(author),
        if (date_iso) |d| toZ(d) else null,
    );

    if (rc != 0)
        return errors.failure(.COMPARE_FAILED, "docx compare failed");

    return errors.success();
}

fn resolveCompareFn() !*const DocxCompareFn {
    if (override_compare_fn) |fn_ptr|
        return fn_ptr;
    if (native_compare_fn) |fn_ptr|
        return fn_ptr;

    const path = try comparerLibraryPath();
    try ensureComparerLibrary(path);
    var lib = try std.DynLib.open(path);
    const sym = lib.lookup(*const DocxCompareFn, compare_symbol) orelse {
        lib.close();
        return error.SymbolMissing;
    };

    native_dynlib = lib;
    native_compare_fn = sym;
    return sym;
}

fn ensureComparerLibrary(path: []const u8) !void {
    std.fs.cwd().access(path, .{}) catch {
        try publishComparer();
        std.fs.cwd().access(path, .{}) catch return CompareError.PublishFailed;
    };
}

fn publishComparer() !void {
    const rid = try detectRid();
    const publish_dir = try std.fmt.allocPrint(std.heap.page_allocator, "src/comparer/publish/{s}", .{rid});
    defer std.heap.page_allocator.free(publish_dir);

    const dotnet = try detectDotnet();
    var argv = [_][]const u8{
        dotnet,
        "publish",
        comparer_project_path,
        "-c",
        "Release",
        "-r",
        rid,
        "-p:PublishAot=true",
        "--self-contained",
        "true",
        "-o",
        publish_dir,
    };

    var child = std.process.Child.init(&argv, std.heap.page_allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return CompareError.PublishFailed,
        else => return CompareError.PublishFailed,
    }
}

fn detectDotnet() ![]const u8 {
    const local = ".dotnet/dotnet";
    if (std.fs.cwd().access(local, .{})) |_| {
        return local;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return CompareError.DotnetNotFound,
    }
    return "dotnet";
}

fn comparerLibraryPath() ![]const u8 {
    if (comparer_path_cache) |p|
        return p;
    const rid = try detectRid();
    const lib_name = try detectLibName();
    const path = try std.fmt.allocPrint(std.heap.page_allocator, "src/comparer/publish/{s}/{s}", .{ rid, lib_name });
    comparer_path_cache = path;
    return path;
}

fn detectRid() ![]const u8 {
    return switch (builtin.target.os.tag) {
        .macos => switch (builtin.target.cpu.arch) {
            .aarch64 => "osx-arm64",
            .x86_64 => "osx-x64",
            else => return CompareError.UnsupportedTarget,
        },
        .linux => switch (builtin.target.cpu.arch) {
            .x86_64 => "linux-x64",
            .aarch64 => "linux-arm64",
            else => return CompareError.UnsupportedTarget,
        },
        .windows => switch (builtin.target.cpu.arch) {
            .x86_64 => "win-x64",
            else => return CompareError.UnsupportedTarget,
        },
        else => return CompareError.UnsupportedTarget,
    };
}

fn detectLibName() ![]const u8 {
    return switch (builtin.target.os.tag) {
        .macos => "EtirComparer.dylib",
        .linux => "EtirComparer.so",
        .windows => "EtirComparer.dll",
        else => return CompareError.UnsupportedTarget,
    };
}

fn toZ(bytes: []const u8) [*:0]const u8 {
    return @as([*:0]const u8, @ptrCast(bytes.ptr));
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn mockDocxCompare(
    before_path: [*:0]const u8,
    after_path: [*:0]const u8,
    out_path: [*:0]const u8,
    author: [*:0]const u8,
    date_iso: ?[*:0]const u8,
) callconv(.c) c_int {
    _ = before_path;
    _ = after_path;
    _ = out_path;
    _ = author;
    _ = date_iso;
    return test_compare_return;
}

fn testSetMockCompareReturn(rc: c_int) void {
    if (!builtin.is_test) return;
    test_compare_return = rc;
    override_compare_fn = mockDocxCompare;
}

fn testResetComparer() void {
    if (!builtin.is_test) return;
    override_compare_fn = null;
    if (native_dynlib) |*lib| {
        lib.close();
        native_dynlib = null;
    }
    native_compare_fn = null;
}

fn tmpAbsPath(allocator: std.mem.Allocator, dir: *std.fs.Dir, rel: []const u8) ![]u8 {
    const root = try dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);
    return std.fs.path.join(allocator, &.{ root, rel });
}

fn testTargetSupportsComparer() bool {
    return detectRid() catch false;
}

fn testExtractDocumentXml(allocator: std.mem.Allocator, docx_path: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "unzip", "-p", docx_path, "word/document.xml" },
    });
    defer allocator.free(result.stderr);
    const stdout_buf = result.stdout;
    errdefer allocator.free(stdout_buf);

    switch (result.term) {
        .Exited => |code| if (code != 0) return error.UnzipFailed,
        else => return error.UnzipFailed,
    }

    return stdout_buf;
}

// Tests ---------------------------------------------------------------------

test "run returns OPEN_FAILED_BEFORE when before docx missing" {
    const res = run("missing-before.docx", "after.docx", "out.docx", "etir", null);
    try std.testing.expect(res == .err);
    try std.testing.expectEqual(errors.Code.OPEN_FAILED_BEFORE, res.err.code);
}

test "run returns OPEN_FAILED_AFTER when after docx missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const before_rel = "before.docx";
    try tmp.dir.writeFile(.{ .sub_path = before_rel, .data = "" });

    const before_abs = try tmpAbsPath(allocator, &tmp.dir, before_rel);
    defer allocator.free(before_abs);

    const after_abs = try tmpAbsPath(allocator, &tmp.dir, "missing.docx");
    defer allocator.free(after_abs);

    const out_abs = try tmpAbsPath(allocator, &tmp.dir, "out.docx");
    defer allocator.free(out_abs);

    const res = run(before_abs, after_abs, out_abs, "etir", null);
    try std.testing.expect(res == .err);
    try std.testing.expectEqual(errors.Code.OPEN_FAILED_AFTER, res.err.code);
}

test "run maps native compare failures to COMPARE_FAILED" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    try tmp.dir.writeFile(.{ .sub_path = "before.docx", .data = "" });
    try tmp.dir.writeFile(.{ .sub_path = "after.docx", .data = "" });

    const before_abs = try tmpAbsPath(allocator, &tmp.dir, "before.docx");
    defer allocator.free(before_abs);
    const after_abs = try tmpAbsPath(allocator, &tmp.dir, "after.docx");
    defer allocator.free(after_abs);
    const out_abs = try tmpAbsPath(allocator, &tmp.dir, "review.docx");
    defer allocator.free(out_abs);

    testSetMockCompareReturn(1);
    defer testResetComparer();

    const res = run(before_abs, after_abs, out_abs, "etir", "2025-11-17T00:00:00Z");
    try std.testing.expect(res == .err);
    try std.testing.expectEqual(errors.Code.COMPARE_FAILED, res.err.code);
}

test "run produces tracked changes review docx" {
    if (!testTargetSupportsComparer()) return;

    testResetComparer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const review_abs = try tmpAbsPath(allocator, &tmp.dir, "review.docx");
    defer allocator.free(review_abs);

    const fixtures_root = try std.fs.cwd().realpathAlloc(allocator, "tests/fixtures");
    defer allocator.free(fixtures_root);

    const before_path = try std.fs.path.join(allocator, &.{ fixtures_root, "before.docx" });
    defer allocator.free(before_path);
    const after_path = try std.fs.path.join(allocator, &.{ fixtures_root, "after.docx" });
    defer allocator.free(after_path);

    const res = run(before_path, after_path, review_abs, "etir", "2025-11-17T00:00:00Z");
    switch (res) {
        .ok => {},
        .err => |failure| {
            std.log.err("docx compare failed during integration test: code={s} msg={s}", .{
                @tagName(failure.code),
                failure.msg,
            });
            return error.TestUnexpectedResult;
        },
    }

    const document_xml = try testExtractDocumentXml(allocator, review_abs);
    defer allocator.free(document_xml);

    try std.testing.expect(std.mem.indexOf(u8, document_xml, "<w:ins") != null);
    try std.testing.expect(std.mem.indexOf(u8, document_xml, "<w:del") != null);
}
