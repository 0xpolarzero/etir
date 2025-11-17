const std = @import("std");

pub const Code = enum(c_int) {
    ok = 0,
    // open/validate
    OPEN_FAILED_BEFORE = 1,
    OPEN_FAILED_AFTER = 2,
    INVALID_DOCX = 3,
    // etir/fingerprint
    ETIR_STALE_BASE = 10,
    // write barriers
    ANCHOR_REMOVED = 20,
    CROSSES_FIELD_INSTRUCTION = 21,
    CROSSES_HYPERLINK_BOUNDARY = 22,
    CROSSES_BOOKMARK_OR_COMMENT = 23,
    UNSUPPORTED_ZONE = 24,
    VALIDATION_FAILED = 25,
    // compare
    COMPARE_FAILED = 40,
    // io
    WRITE_FAILED_OUT = 50,
    INTERNAL = 99,
};

pub const Failure = struct {
    code: Code,
    msg: []const u8,
};

pub const Result = union(enum) {
    ok,
    err: Failure,
};

pub fn success() Result {
    return .ok;
}

pub fn failure(code: Code, msg: []const u8) Result {
    const resolved = if (msg.len == 0) message(code) else msg;
    return .{ .err = .{ .code = code, .msg = resolved } };
}

pub fn message(code: Code) []const u8 {
    return switch (code) {
        .ok => "ok",
        .OPEN_FAILED_BEFORE => "failed to open 'before' DOCX",
        .OPEN_FAILED_AFTER => "failed to open 'after' DOCX",
        .INVALID_DOCX => "invalid or repairable DOCX",
        .ETIR_STALE_BASE => "ETIR fingerprint does not match base DOCX",
        .ANCHOR_REMOVED => "edit removed or moved an anchor in strict mode",
        .CROSSES_FIELD_INSTRUCTION => "edit crosses a field instruction barrier",
        .CROSSES_HYPERLINK_BOUNDARY => "edit crosses a hyperlink boundary",
        .CROSSES_BOOKMARK_OR_COMMENT => "edit crosses a bookmark/comment boundary",
        .UNSUPPORTED_ZONE => "edit targets an unsupported zone",
        .VALIDATION_FAILED => "post-write validation failed",
        .COMPARE_FAILED => "compare engine failed",
        .WRITE_FAILED_OUT => "failed writing output DOCX",
        .INTERNAL => "internal error",
    };
}

fn validateMessages() !void {
    inline for (std.meta.tags(Code)) |tag| {
        try std.testing.expect(message(tag).len > 0);
    }
}

const Unexpected = error{unexpected_success};

fn failureFallsBack() !void {
    const res = failure(.INVALID_DOCX, "");
    switch (res) {
        .ok => return Unexpected.unexpected_success,
        .err => |err_state| {
            try std.testing.expectEqual(.INVALID_DOCX, err_state.code);
            try std.testing.expectEqualStrings(message(.INVALID_DOCX), err_state.msg);
        },
    }
}

fn failureReturnsCustomMessage() !void {
    const res = failure(.COMPARE_FAILED, "docx comparer exploded");
    switch (res) {
        .ok => return Unexpected.unexpected_success,
        .err => |err_state| {
            try std.testing.expectEqualStrings("docx comparer exploded", err_state.msg);
        },
    }
}

test "every code has a non-empty canonical message" {
    try validateMessages();
}

test "failure helper falls back to canonical message when no override" {
    try failureFallsBack();
}

test "failure helper preserves explicit message" {
    try failureReturnsCustomMessage();
}
