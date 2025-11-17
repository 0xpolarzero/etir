const std = @import("std");
const ManagedArrayList = std.array_list.Managed;

pub const JsonError = error{
    UnexpectedToken,
    UnexpectedEnd,
    UnterminatedString,
    InvalidEscape,
    InvalidUnicodeEscape,
    InvalidSurrogatePair,
    InvalidNumber,
    OutOfMemory,
};

pub const WriterError = error{
    InvalidState,
    MissingKey,
    UnclosedContainer,
    IncompleteDocument,
};

pub fn Writer(comptime WriterType: type) type {
    return struct {
        const Self = @This();
        const Frame = struct {
            kind: Kind,
            element_count: usize = 0,
            expecting_key: bool,
        };
        const Kind = enum { object, array };

        allocator: std.mem.Allocator,
        writer: WriterType,
        stack: std.ArrayListUnmanaged(Frame) = .{},
        root_started: bool = false,
        root_completed: bool = false,

        pub fn init(allocator: std.mem.Allocator, writer: WriterType) Self {
            return .{
                .allocator = allocator,
                .writer = writer,
            };
        }

        pub fn deinit(self: *Self) void {
            self.stack.deinit(self.allocator);
        }

        pub fn beginObject(self: *Self) (WriterError || WriterType.Error)!void {
            try self.prepareValue();
            try self.writer.writeByte('{');
            try self.stack.append(self.allocator, .{
                .kind = .object,
                .expecting_key = true,
            });
        }

        pub fn endObject(self: *Self) (WriterError || WriterType.Error)!void {
            const frame = self.popFrame() orelse return WriterError.UnclosedContainer;
            if (frame.kind != .object or !frame.expecting_key) return WriterError.InvalidState;
            try self.writer.writeByte('}');
            try self.completeValue();
        }

        pub fn beginArray(self: *Self) (WriterError || WriterType.Error)!void {
            try self.prepareValue();
            try self.writer.writeByte('[');
            try self.stack.append(self.allocator, .{
                .kind = .array,
                .expecting_key = false,
            });
        }

        pub fn endArray(self: *Self) (WriterError || WriterType.Error)!void {
            const frame = self.popFrame() orelse return WriterError.UnclosedContainer;
            if (frame.kind != .array) return WriterError.InvalidState;
            try self.writer.writeByte(']');
            try self.completeValue();
        }

        pub fn key(self: *Self, name: []const u8) (WriterError || WriterType.Error)!void {
            const frame = self.currentObjectFrame() orelse return WriterError.InvalidState;
            if (!frame.expecting_key) return WriterError.InvalidState;
            if (frame.element_count > 0) try self.writer.writeByte(',');
            try writeStringLiteral(self.writer, name);
            try self.writer.writeByte(':');
            frame.expecting_key = false;
        }

        pub fn string(self: *Self, value: []const u8) (WriterError || WriterType.Error)!void {
            try self.prepareValue();
            try writeStringLiteral(self.writer, value);
            try self.completeValue();
        }

        pub fn boolValue(self: *Self, value: bool) (WriterError || WriterType.Error)!void {
            try self.prepareValue();
            if (value) {
                try self.writer.writeAll("true");
            } else {
                try self.writer.writeAll("false");
            }
            try self.completeValue();
        }

        pub fn nullValue(self: *Self) (WriterError || WriterType.Error)!void {
            try self.prepareValue();
            try self.writer.writeAll("null");
            try self.completeValue();
        }

        pub fn number(self: *Self, value: anytype) (WriterError || WriterType.Error)!void {
            try self.prepareValue();
            try std.fmt.format(self.writer, "{}", .{value});
            try self.completeValue();
        }

        pub fn finish(self: *Self) WriterError!void {
            if (self.stack.items.len != 0) return WriterError.UnclosedContainer;
            if (!self.root_completed) return WriterError.IncompleteDocument;
        }

        fn currentObjectFrame(self: *Self) ?*Frame {
            if (self.stack.items.len == 0) return null;
            const frame = &self.stack.items[self.stack.items.len - 1];
            return if (frame.kind == .object) frame else null;
        }

        fn prepareValue(self: *Self) (WriterError || WriterType.Error)!void {
            if (self.stack.items.len == 0) {
                if (self.root_started and !self.root_completed) return WriterError.InvalidState;
                if (self.root_completed) return WriterError.InvalidState;
                self.root_started = true;
                return;
            }
            const frame = &self.stack.items[self.stack.items.len - 1];
            switch (frame.kind) {
                .array => {
                    if (frame.element_count > 0) try self.writer.writeByte(',');
                },
                .object => {
                    if (frame.expecting_key) return WriterError.MissingKey;
                },
            }
        }

        fn completeValue(self: *Self) WriterError!void {
            if (self.stack.items.len == 0) {
                self.root_completed = true;
                return;
            }
            const frame = &self.stack.items[self.stack.items.len - 1];
            switch (frame.kind) {
                .array => frame.element_count += 1,
                .object => {
                    frame.element_count += 1;
                    frame.expecting_key = true;
                },
            }
        }

        fn popFrame(self: *Self) ?Frame {
            if (self.stack.items.len == 0) return null;
            const new_len = self.stack.items.len - 1;
            const frame = self.stack.items[new_len];
            self.stack.items.len = new_len;
            return frame;
        }
    };
}

fn writeStringLiteral(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    var start: usize = 0;
    for (value, 0..) |byte, idx| {
        if (byte == '"' or byte == '\\' or byte < 0x20) {
            if (idx > start) try writer.writeAll(value[start..idx]);
            switch (byte) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                0x08 => try writer.writeAll("\\b"),
                0x0C => try writer.writeAll("\\f"),
                0x0A => try writer.writeAll("\\n"),
                0x0D => try writer.writeAll("\\r"),
                0x09 => try writer.writeAll("\\t"),
                else => {
                    var buf: [6]u8 = undefined;
                    buf[0] = '\\';
                    buf[1] = 'u';
                    buf[2] = '0';
                    buf[3] = '0';
                    buf[4] = hex(byte >> 4);
                    buf[5] = hex(byte & 0xF);
                    try writer.writeAll(&buf);
                },
            }
            start = idx + 1;
        }
    }
    if (start < value.len) try writer.writeAll(value[start..]);
    try writer.writeByte('"');
}

fn hex(nibble: u8) u8 {
    return "0123456789abcdef"[nibble & 0x0F];
}

pub const Reader = struct {
    data: []const u8,
    index: usize = 0,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data };
    }

    pub fn skipWhitespace(self: *Reader) void {
        while (self.index < self.data.len) : (self.index += 1) {
            const ch = self.data[self.index];
            if (ch != ' ' and ch != '\n' and ch != '\t' and ch != '\r') break;
        }
    }

    pub fn peek(self: Reader) ?u8 {
        if (self.index >= self.data.len) return null;
        return self.data[self.index];
    }

    pub fn expectChar(self: *Reader, ch: u8) JsonError!void {
        self.skipWhitespace();
        if (self.index >= self.data.len or self.data[self.index] != ch) {
            return JsonError.UnexpectedToken;
        }
        self.index += 1;
    }

    pub fn beginObject(self: *Reader) JsonError!void {
        try self.expectChar('{');
    }

    pub fn endObject(self: *Reader) JsonError!void {
        try self.expectChar('}');
    }

    pub fn beginArray(self: *Reader) JsonError!void {
        try self.expectChar('[');
    }

    pub fn endArray(self: *Reader) JsonError!void {
        try self.expectChar(']');
    }

    pub fn readStringAlloc(self: *Reader, allocator: std.mem.Allocator) JsonError![]u8 {
        self.skipWhitespace();
        if (self.index >= self.data.len or self.data[self.index] != '"') return JsonError.UnexpectedToken;
        self.index += 1;
        var list = ManagedArrayList(u8).init(allocator);
        errdefer list.deinit();
        var start = self.index;
        while (self.index < self.data.len) {
            const ch = self.data[self.index];
            if (ch == '"') {
                if (self.index > start) try list.appendSlice(self.data[start..self.index]);
                self.index += 1;
                return list.toOwnedSlice();
            }
            if (ch == '\\') {
                if (self.index > start) try list.appendSlice(self.data[start..self.index]);
                self.index += 1;
                try self.decodeEscape(&list);
                start = self.index;
                continue;
            }
            if (ch < 0x20) return JsonError.UnexpectedToken;
            self.index += 1;
        }
        return JsonError.UnterminatedString;
    }

    pub fn readNumberSlice(self: *Reader) JsonError![]const u8 {
        self.skipWhitespace();
        const start = self.index;
        if (start >= self.data.len) return JsonError.UnexpectedEnd;
        if (self.data[self.index] == '-') {
            self.index += 1;
            if (self.index >= self.data.len) return JsonError.InvalidNumber;
        }
        if (self.data[self.index] == '0') {
            self.index += 1;
            if (self.index < self.data.len and std.ascii.isDigit(self.data[self.index])) {
                return JsonError.InvalidNumber;
            }
        } else if (std.ascii.isDigit(self.data[self.index])) {
            while (self.index < self.data.len and std.ascii.isDigit(self.data[self.index])) : (self.index += 1) {}
        } else return JsonError.InvalidNumber;

        if (self.index < self.data.len and self.data[self.index] == '.') {
            self.index += 1;
            if (self.index >= self.data.len or !std.ascii.isDigit(self.data[self.index])) return JsonError.InvalidNumber;
            while (self.index < self.data.len and std.ascii.isDigit(self.data[self.index])) : (self.index += 1) {}
        }

        if (self.index < self.data.len and (self.data[self.index] == 'e' or self.data[self.index] == 'E')) {
            self.index += 1;
            if (self.index < self.data.len and (self.data[self.index] == '+' or self.data[self.index] == '-')) {
                self.index += 1;
            }
            if (self.index >= self.data.len or !std.ascii.isDigit(self.data[self.index])) return JsonError.InvalidNumber;
            while (self.index < self.data.len and std.ascii.isDigit(self.data[self.index])) : (self.index += 1) {}
        }

        return self.data[start..self.index];
    }

    pub fn readBool(self: *Reader) JsonError!bool {
        self.skipWhitespace();
        if (self.data[self.index..].len >= 4 and std.mem.startsWith(u8, self.data[self.index..], "true")) {
            self.index += 4;
            return true;
        }
        if (self.data[self.index..].len >= 5 and std.mem.startsWith(u8, self.data[self.index..], "false")) {
            self.index += 5;
            return false;
        }
        return JsonError.UnexpectedToken;
    }

    pub fn readNull(self: *Reader) JsonError!void {
        self.skipWhitespace();
        if (self.data[self.index..].len < 4 or !std.mem.startsWith(u8, self.data[self.index..], "null")) {
            return JsonError.UnexpectedToken;
        }
        self.index += 4;
    }

    pub fn isEof(self: Reader) bool {
        var r = self;
        r.skipWhitespace();
        return r.index >= r.data.len;
    }

    fn decodeEscape(self: *Reader, list: *ManagedArrayList(u8)) JsonError!void {
        if (self.index >= self.data.len) return JsonError.UnexpectedEnd;
        const ch = self.data[self.index];
        self.index += 1;
        switch (ch) {
            '"' => try list.append('"'),
            '\\' => try list.append('\\'),
            '/' => try list.append('/'),
            'b' => try list.append(0x08),
            'f' => try list.append(0x0C),
            'n' => try list.append('\n'),
            'r' => try list.append('\r'),
            't' => try list.append('\t'),
            'u' => {
                const code = try self.readUnicodeEscape();
                try appendCodepoint(list, code);
            },
            else => return JsonError.InvalidEscape,
        }
    }

    fn readUnicodeEscape(self: *Reader) JsonError!u21 {
        const first = try self.readUnicodeUnit();
        if (first >= 0xD800 and first <= 0xDBFF) {
            if (self.index + 6 > self.data.len or self.data[self.index] != '\\' or self.data[self.index + 1] != 'u') {
                return JsonError.InvalidSurrogatePair;
            }
            self.index += 2;
            const low = try self.readUnicodeUnit();
            if (low < 0xDC00 or low > 0xDFFF) return JsonError.InvalidSurrogatePair;
            const high = first - 0xD800;
            const low_bits = low - 0xDC00;
            return @as(u21, 0x10000) + (high << 10) + low_bits;
        }
        if (first >= 0xDC00 and first <= 0xDFFF) return JsonError.InvalidSurrogatePair;
        return first;
    }

    fn readUnicodeUnit(self: *Reader) JsonError!u21 {
        if (self.index + 4 > self.data.len) return JsonError.UnexpectedEnd;
        var value: u21 = 0;
        for (self.data[self.index .. self.index + 4]) |digit| {
            const nibble = hexValue(digit) orelse return JsonError.InvalidUnicodeEscape;
            value = (value << 4) | nibble;
        }
        self.index += 4;
        return value;
    }
};

fn hexValue(ch: u8) ?u21 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'a'...'f' => 10 + (ch - 'a'),
        'A'...'F' => 10 + (ch - 'A'),
        else => null,
    };
}

fn appendCodepoint(list: *ManagedArrayList(u8), cp: u21) JsonError!void {
    var buf: [4]u8 = undefined;
    const written = std.unicode.utf8Encode(cp, &buf) catch return JsonError.InvalidUnicodeEscape;
    try list.appendSlice(buf[0..written]);
}

test "json writer builds nested structure" {
    var buffer = ManagedArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var writer = Writer(@TypeOf(buffer.writer())).init(std.testing.allocator, buffer.writer());
    defer writer.deinit();
    try writer.beginObject();
    try writer.key("message");
    try writer.string("hello");
    try writer.key("values");
    try writer.beginArray();
    try writer.number(42);
    try writer.boolValue(true);
    try writer.nullValue();
    try writer.endArray();
    try writer.endObject();
    try writer.finish();
    try std.testing.expectEqualStrings("{\"message\":\"hello\",\"values\":[42,true,null]}", buffer.items);
}

test "json reader parses escapes and numbers" {
    const source = "\"hi\\n\\uD83D\\uDE00\" 123.45e-2 true null";
    var reader = Reader.init(source);
    const str = try reader.readStringAlloc(std.testing.allocator);
    defer std.testing.allocator.free(str);
    try std.testing.expectEqualStrings("hi\n😀", str);
    const num = try reader.readNumberSlice();
    try std.testing.expectEqualStrings("123.45e-2", num);
    try std.testing.expect(try reader.readBool());
    try reader.readNull();
    try std.testing.expect(reader.isEof());
}
