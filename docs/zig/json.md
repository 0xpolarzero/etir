# JSON in Zig 0.15.2: Complete Guide

Zig's standard library provides comprehensive JSON support conforming to RFC 8259. Here's everything you need to know:

## Overview

The JSON module offers both high-level and low-level APIs for parsing and stringifying JSON data. [1](#0-0) 

## 1. Parsing JSON

### Basic Parsing into Structs

The most common way to parse JSON is using `parseFromSlice`, which deserializes JSON directly into Zig types: [2](#0-1) 

**Key points:**
- You must call `deinit()` on the returned `Parsed` object to free memory
- The function returns a `Parsed(T)` wrapper containing an arena allocator and your value
- Default struct field values are used for missing JSON fields [3](#0-2) 

### Parsing into Dynamic Values

For runtime inspection of unknown JSON structures, parse into `Value`: [4](#0-3) 

The `Value` type is a tagged union that can represent any JSON value: [5](#0-4) 

### Parse Options

Control parsing behavior with `ParseOptions`: [6](#0-5) 

**Important options:**
- `duplicate_field_behavior`: How to handle duplicate object keys (`.use_first`, `.@"error"`, `.use_last`)
- `ignore_unknown_fields`: Whether to ignore fields not in your struct
- `max_value_len`: Maximum length for string/number values
- `allocate`: When to allocate vs reference input buffer
- `parse_numbers`: Whether to parse numbers or keep them as strings

### Leaky Parsing

If using an arena allocator, use the "leaky" variants for simpler code: [7](#0-6) 

### Parsing from Streams

For streaming input (like files or network), use `Reader`: [8](#0-7) 

## 2. Stringifying JSON

### Basic Stringification

The high-level `stringify` function (available via `Stringify.value`) serializes Zig values to JSON: [9](#0-8) 

You can also use the `fmt` helper for integration with Zig's formatting system: [10](#0-9) 

### Low-Level Streaming API

For more control, use the `Stringify` struct directly: [11](#0-10) 

The streaming API follows a specific grammar: [12](#0-11) 

### Stringify Options

Control output formatting with `Options`: [13](#0-12) 

**Key options:**
- `whitespace`: Control indentation (`.minified`, `.indent_2`, `.indent_4`, `.indent_tab`, etc.)
- `emit_null_optional_fields`: Whether to include null optional fields
- `emit_strings_as_arrays`: Emit byte arrays as number arrays instead of strings
- `escape_unicode`: Whether to escape unicode characters
- `emit_nonportable_numbers_as_strings`: Stringify large integers as strings for JavaScript compatibility

### Type Support

The stringify system supports extensive Zig types: [14](#0-13) 

## 3. Custom Parsing and Stringification

### Custom Parsing

Implement `jsonParse` method on your type for custom parsing logic: [15](#0-14) 

For parsing from already-parsed `Value` objects, implement `jsonParseFromValue`: [16](#0-15) 

### Custom Stringification

Implement `jsonStringify` method for custom serialization: [17](#0-16) 

The `Value` type shows a complete example: [18](#0-17) 

## 4. Low-Level Scanner API

For maximum control, use the `Scanner` directly to tokenize JSON: [19](#0-18) 

## 5. Type Mappings

**Parsing mappings:**
- JSON `true`/`false` → Zig `bool`
- JSON number → Zig integers/floats
- JSON `null` → Zig optional (`?T`)
- JSON string → Zig string slices (`[]const u8`, `[]u8`)
- JSON array → Zig arrays, slices, tuples
- JSON object → Zig structs
- Tagged unions serialize as `{"tag": value}` [20](#0-19) 

**Stringification:** [21](#0-20) 

## 6. Error Handling

Parsing can return various errors: [22](#0-21) 

## Notes

- Always call `deinit()` on `Parsed` results unless using arena allocators
- The `parseFromSlice` API automatically handles the entire JSON document including validation
- For streaming very large JSON, use `Reader` with a streaming source
- Custom `jsonParse`/`jsonStringify` methods give you full control over serialization
- The library handles UTF-8 validation and proper escaping automatically
- Sentinel-terminated slices and arrays are fully supported
- Union types must be tagged (non-tagged unions cannot be parsed/stringified)

### Citations

**File:** lib/std/json.zig (L1-10)
```zig
//! JSON parsing and stringification conforming to RFC 8259. https://datatracker.ietf.org/doc/html/rfc8259
//!
//! The low-level `Scanner` API produces `Token`s from an input slice or successive slices of inputs,
//! The `Reader` API connects a `std.Io.GenericReader` to a `Scanner`.
//!
//! The high-level `parseFromSlice` and `parseFromTokenSource` deserialize a JSON document into a Zig type.
//! Parse into a dynamically-typed `Value` to load any JSON value for runtime inspection.
//!
//! The low-level `writeStream` emits syntax-conformant JSON tokens to a `std.Io.Writer`.
//! The high-level `stringify` serializes a Zig or `Value` type into JSON.
```

**File:** lib/std/json.zig (L16-24)
```zig
test Scanner {
    var scanner = Scanner.initCompleteInput(testing.allocator, "{\"foo\": 123}\n");
    defer scanner.deinit();
    try testing.expectEqual(Token.object_begin, try scanner.next());
    try testing.expectEqualSlices(u8, "foo", (try scanner.next()).string);
    try testing.expectEqualSlices(u8, "123", (try scanner.next()).number);
    try testing.expectEqual(Token.object_end, try scanner.next());
    try testing.expectEqual(Token.end_of_document, try scanner.next());
}
```

**File:** lib/std/json.zig (L26-36)
```zig
test parseFromSlice {
    var parsed_str = try parseFromSlice([]const u8, testing.allocator, "\"a\\u0020b\"", .{});
    defer parsed_str.deinit();
    try testing.expectEqualSlices(u8, "a b", parsed_str.value);

    const T = struct { a: i32 = -1, b: [2]u8 };
    var parsed_struct = try parseFromSlice(T, testing.allocator, "{\"b\":\"xy\"}", .{});
    defer parsed_struct.deinit();
    try testing.expectEqual(@as(i32, -1), parsed_struct.value.a); // default value
    try testing.expectEqualSlices(u8, "xy", parsed_struct.value.b[0..]);
}
```

**File:** lib/std/json.zig (L38-42)
```zig
test Value {
    var parsed = try parseFromSlice(Value, testing.allocator, "{\"anything\": \"goes\"}", .{});
    defer parsed.deinit();
    try testing.expectEqualSlices(u8, "goes", parsed.value.object.get("anything").?.string);
}
```

**File:** lib/std/json.zig (L44-61)
```zig
test Stringify {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    var write_stream: Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    defer out.deinit();
    try write_stream.beginObject();
    try write_stream.objectField("foo");
    try write_stream.write(123);
    try write_stream.endObject();
    const expected =
        \\{
        \\  "foo": 123
        \\}
    ;
    try testing.expectEqualSlices(u8, expected, out.written());
}
```

**File:** lib/std/json.zig (L96-117)
```zig
/// Returns a formatter that formats the given value using stringify.
pub fn fmt(value: anytype, options: Stringify.Options) Formatter(@TypeOf(value)) {
    return Formatter(@TypeOf(value)){ .value = value, .options = options };
}

test fmt {
    const expectFmt = std.testing.expectFmt;
    try expectFmt("123", "{f}", .{fmt(@as(u32, 123), .{})});
    try expectFmt(
        \\{"num":927,"msg":"hello","sub":{"mybool":true}}
    , "{f}", .{fmt(struct {
        num: u32,
        msg: []const u8,
        sub: struct {
            mybool: bool,
        },
    }{
        .num = 927,
        .msg = "hello",
        .sub = .{ .mybool = true },
    }, .{})});
}
```

**File:** lib/std/json/static.zig (L16-54)
```zig
/// Controls how to deal with various inconsistencies between the JSON document and the Zig struct type passed in.
/// For duplicate fields or unknown fields, set options in this struct.
/// For missing fields, give the Zig struct fields default values.
pub const ParseOptions = struct {
    /// Behaviour when a duplicate field is encountered.
    /// The default is to return `error.DuplicateField`.
    duplicate_field_behavior: enum {
        use_first,
        @"error",
        use_last,
    } = .@"error",

    /// If false, finding an unknown field returns `error.UnknownField`.
    ignore_unknown_fields: bool = false,

    /// Passed to `std.json.Scanner.nextAllocMax` or `std.json.Reader.nextAllocMax`.
    /// The default for `parseFromSlice` or `parseFromTokenSource` with a `*std.json.Scanner` input
    /// is the length of the input slice, which means `error.ValueTooLong` will never be returned.
    /// The default for `parseFromTokenSource` with a `*std.json.Reader` is `std.json.default_max_value_len`.
    /// Ignored for `parseFromValue` and `parseFromValueLeaky`.
    max_value_len: ?usize = null,

    /// This determines whether strings should always be copied,
    /// or if a reference to the given buffer should be preferred if possible.
    /// The default for `parseFromSlice` or `parseFromTokenSource` with a `*std.json.Scanner` input
    /// is `.alloc_if_needed`.
    /// The default with a `*std.json.Reader` input is `.alloc_always`.
    /// Ignored for `parseFromValue` and `parseFromValueLeaky`.
    allocate: ?AllocWhen = null,

    /// When parsing to a `std.json.Value`, set this option to false to always emit
    /// JSON numbers as unparsed `std.json.Value.number_string`.
    /// Otherwise, JSON numbers are parsed as either `std.json.Value.integer`,
    /// `std.json.Value.float` or left as unparsed `std.json.Value.number_string`
    /// depending on the format and value of the JSON number.
    /// When this option is true, JSON numbers encoded as floats (see `std.json.isNumberFormattedLikeAnInteger`)
    /// may lose precision when being parsed into `std.json.Value.float`.
    parse_numbers: bool = true,
};
```

**File:** lib/std/json/static.zig (L56-67)
```zig
pub fn Parsed(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}
```

**File:** lib/std/json/static.zig (L85-98)
```zig
/// Parses the json document from `s` and returns the result.
/// Allocations made during this operation are not carefully tracked and may not be possible to individually clean up.
/// It is recommended to use a `std.heap.ArenaAllocator` or similar.
pub fn parseFromSliceLeaky(
    comptime T: type,
    allocator: Allocator,
    s: []const u8,
    options: ParseOptions,
) ParseError(Scanner)!T {
    var scanner = Scanner.initCompleteInput(allocator, s);
    defer scanner.deinit();

    return parseFromTokenSourceLeaky(T, allocator, &scanner, options);
}
```

**File:** lib/std/json/static.zig (L100-119)
```zig
/// `scanner_or_reader` must be either a `*std.json.Scanner` with complete input or a `*std.json.Reader`.
/// Note that `error.BufferUnderrun` is not actually possible to return from this function.
pub fn parseFromTokenSource(
    comptime T: type,
    allocator: Allocator,
    scanner_or_reader: anytype,
    options: ParseOptions,
) ParseError(@TypeOf(scanner_or_reader.*))!Parsed(T) {
    var parsed = Parsed(T){
        .arena = try allocator.create(ArenaAllocator),
        .value = undefined,
    };
    errdefer allocator.destroy(parsed.arena);
    parsed.arena.* = ArenaAllocator.init(allocator);
    errdefer parsed.arena.deinit();

    parsed.value = try parseFromTokenSourceLeaky(T, parsed.arena.allocator(), scanner_or_reader, options);

    return parsed;
}
```

**File:** lib/std/json/static.zig (L197-206)
```zig
pub const ParseFromValueError = std.fmt.ParseIntError || std.fmt.ParseFloatError || Allocator.Error || error{
    UnexpectedToken,
    InvalidNumber,
    Overflow,
    InvalidEnumTag,
    DuplicateField,
    UnknownField,
    MissingField,
    LengthMismatch,
};
```

**File:** lib/std/json/static.zig (L221-257)
```zig
    switch (@typeInfo(T)) {
        .bool => {
            return switch (try source.next()) {
                .true => true,
                .false => false,
                else => error.UnexpectedToken,
            };
        },
        .float, .comptime_float => {
            const token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
            defer freeAllocated(allocator, token);
            const slice = switch (token) {
                inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                else => return error.UnexpectedToken,
            };
            return try std.fmt.parseFloat(T, slice);
        },
        .int, .comptime_int => {
            const token = try source.nextAllocMax(allocator, .alloc_if_needed, options.max_value_len.?);
            defer freeAllocated(allocator, token);
            const slice = switch (token) {
                inline .number, .allocated_number, .string, .allocated_string => |slice| slice,
                else => return error.UnexpectedToken,
            };
            return sliceToInt(T, slice);
        },
        .optional => |optionalInfo| {
            switch (try source.peekNextTokenType()) {
                .null => {
                    _ = try source.next();
                    return null;
                },
                else => {
                    return try innerParse(optionalInfo.child, allocator, source, options);
                },
            }
        },
```

**File:** lib/std/json/dynamic.zig (L16-28)
```zig
/// Represents any JSON value, potentially containing other JSON values.
/// A .float value may be an approximation of the original value.
/// Arbitrary precision numbers can be represented by .number_string values.
/// See also `std.json.ParseOptions.parse_numbers`.
pub const Value = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    number_string: []const u8,
    string: []const u8,
    array: Array,
    object: ObjectMap,
```

**File:** lib/std/json/dynamic.zig (L56-75)
```zig
    pub fn jsonStringify(value: @This(), jws: anytype) !void {
        switch (value) {
            .null => try jws.write(null),
            .bool => |inner| try jws.write(inner),
            .integer => |inner| try jws.write(inner),
            .float => |inner| try jws.write(inner),
            .number_string => |inner| try jws.print("{s}", .{inner}),
            .string => |inner| try jws.write(inner),
            .array => |inner| try jws.write(inner.items),
            .object => |inner| {
                try jws.beginObject();
                var it = inner.iterator();
                while (it.next()) |entry| {
                    try jws.objectField(entry.key_ptr.*);
                    try jws.write(entry.value_ptr.*);
                }
                try jws.endObject();
            },
        }
    }
```

**File:** lib/std/json/Stringify.zig (L1-18)
```zig
//! Writes JSON ([RFC8259](https://tools.ietf.org/html/rfc8259)) formatted data
//! to a stream.
//!
//! The sequence of method calls to write JSON content must follow this grammar:
//! ```
//!  <once> = <value>
//!  <value> =
//!    | <object>
//!    | <array>
//!    | write
//!    | print
//!    | <writeRawStream>
//!  <object> = beginObject ( <field> <value> )* endObject
//!  <field> = objectField | objectFieldRaw | <objectFieldRawStream>
//!  <array> = beginArray ( <value> )* endArray
//!  <writeRawStream> = beginWriteRaw ( stream.writeAll )* endWriteRaw
//!  <objectFieldRawStream> = beginObjectFieldRaw ( stream.writeAll )* endObjectFieldRaw
//! ```
```

**File:** lib/std/json/Stringify.zig (L318-346)
```zig
/// Renders the given Zig value as JSON.
///
/// Supported types:
///  * Zig `bool` -> JSON `true` or `false`.
///  * Zig `?T` -> `null` or the rendering of `T`.
///  * Zig `i32`, `u64`, etc. -> JSON number or string.
///      * When option `emit_nonportable_numbers_as_strings` is true, if the value is outside the range `+-1<<53` (the precise integer range of f64), it is rendered as a JSON string in base 10. Otherwise, it is rendered as JSON number.
///  * Zig floats -> JSON number or string.
///      * If the value cannot be precisely represented by an f64, it is rendered as a JSON string. Otherwise, it is rendered as JSON number.
///      * TODO: Float rendering will likely change in the future, e.g. to remove the unnecessary "e+00".
///  * Zig `[]const u8`, `[]u8`, `*[N]u8`, `@Vector(N, u8)`, and similar -> JSON string.
///      * See `Options.emit_strings_as_arrays`.
///      * If the content is not valid UTF-8, rendered as an array of numbers instead.
///  * Zig `[]T`, `[N]T`, `*[N]T`, `@Vector(N, T)`, and similar -> JSON array of the rendering of each item.
///  * Zig tuple -> JSON array of the rendering of each item.
///  * Zig `struct` -> JSON object with each field in declaration order.
///      * If the struct declares a method `pub fn jsonStringify(self: *@This(), jw: anytype) !void`, it is called to do the serialization instead of the default behavior. The given `jw` is a pointer to this `Stringify`. See `std.json.Value` for an example.
///      * See `Options.emit_null_optional_fields`.
///  * Zig `union(enum)` -> JSON object with one field named for the active tag and a value representing the payload.
///      * If the payload is `void`, then the emitted value is `{}`.
///      * If the union declares a method `pub fn jsonStringify(self: *@This(), jw: anytype) !void`, it is called to do the serialization instead of the default behavior. The given `jw` is a pointer to this `Stringify`.
///  * Zig `enum` -> JSON string naming the active tag.
///      * If the enum declares a method `pub fn jsonStringify(self: *@This(), jw: anytype) !void`, it is called to do the serialization instead of the default behavior. The given `jw` is a pointer to this `Stringify`.
///      * If the enum is non-exhaustive, unnamed values are rendered as integers.
///  * Zig untyped enum literal -> JSON string naming the active tag.
///  * Zig error -> JSON string naming the error.
///  * Zig `*T` -> the rendering of `T`. Note there is no guard against circular-reference infinite recursion.
///
/// See also alternative functions `print` and `beginWriteRaw`.
```

**File:** lib/std/json/Stringify.zig (L348-398)
```zig
pub fn write(self: *Stringify, v: anytype) Error!void {
    if (build_mode_has_safety) assert(self.raw_streaming_mode == .none);
    const T = @TypeOf(v);
    switch (@typeInfo(T)) {
        .int => {
            try self.valueStart();
            if (self.options.emit_nonportable_numbers_as_strings and
                (v <= -(1 << 53) or v >= (1 << 53)))
            {
                try self.writer.print("\"{}\"", .{v});
            } else {
                try self.writer.print("{}", .{v});
            }
            self.valueDone();
            return;
        },
        .comptime_int => {
            return self.write(@as(std.math.IntFittingRange(v, v), v));
        },
        .float, .comptime_float => {
            if (@as(f64, @floatCast(v)) == v) {
                try self.valueStart();
                try self.writer.print("{}", .{@as(f64, @floatCast(v))});
                self.valueDone();
                return;
            }
            try self.valueStart();
            try self.writer.print("\"{}\"", .{v});
            self.valueDone();
            return;
        },

        .bool => {
            try self.valueStart();
            try self.writer.writeAll(if (v) "true" else "false");
            self.valueDone();
            return;
        },
        .null => {
            try self.valueStart();
            try self.writer.writeAll("null");
            self.valueDone();
            return;
        },
        .optional => {
            if (v) |payload| {
                return try self.write(payload);
            } else {
                return try self.write(null);
            }
        },
```

**File:** lib/std/json/Stringify.zig (L539-568)
```zig
pub const Options = struct {
    /// Controls the whitespace emitted.
    /// The default `.minified` is a compact encoding with no whitespace between tokens.
    /// Any setting other than `.minified` will use newlines, indentation, and a space after each ':'.
    /// `.indent_1` means 1 space for each indentation level, `.indent_2` means 2 spaces, etc.
    /// `.indent_tab` uses a tab for each indentation level.
    whitespace: enum {
        minified,
        indent_1,
        indent_2,
        indent_3,
        indent_4,
        indent_8,
        indent_tab,
    } = .minified,

    /// Should optional fields with null value be written?
    emit_null_optional_fields: bool = true,

    /// Arrays/slices of u8 are typically encoded as JSON strings.
    /// This option emits them as arrays of numbers instead.
    /// Does not affect calls to `objectField*()`.
    emit_strings_as_arrays: bool = false,

    /// Should unicode characters be escaped in strings?
    escape_unicode: bool = false,

    /// When true, renders numbers outside the range `+-1<<53` (the precise integer range of f64) as JSON strings in base 10.
    emit_nonportable_numbers_as_strings: bool = false,
};
```

**File:** lib/std/json/Stringify.zig (L570-576)
```zig
/// Writes the given value to the `Writer` writer.
/// See `Stringify` for how the given value is serialized into JSON.
/// The maximum nesting depth of the output JSON document is 256.
pub fn value(v: anytype, options: Options, writer: *Writer) Error!void {
    var s: Stringify = .{ .writer = writer, .options = options };
    try s.write(v);
}
```

**File:** lib/std/json/Stringify.zig (L956-968)
```zig
test "stringify struct with custom stringifier" {
    try testStringify("[\"something special\",42]", struct {
        foo: u32,
        const Self = @This();
        pub fn jsonStringify(v: @This(), jws: anytype) !void {
            _ = v;
            try jws.beginArray();
            try jws.write("something special");
            try jws.write(42);
            try jws.endArray();
        }
    }{ .foo = 42 }, .{});
}
```

**File:** lib/std/json/static_test.zig (L229-242)
```zig
    custom_struct: struct {
        pub fn jsonParse(allocator: Allocator, source: anytype, options: ParseOptions) !@This() {
            _ = allocator;
            _ = options;
            try source.skipValue();
            return @This(){};
        }
        pub fn jsonParseFromValue(allocator: Allocator, source: Value, options: ParseOptions) !@This() {
            _ = allocator;
            _ = source;
            _ = options;
            return @This(){};
        }
    },
```
