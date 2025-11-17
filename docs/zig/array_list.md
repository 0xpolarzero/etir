# ArrayList in Zig 0.15.2

`ArrayList` is a contiguous, growable list of items in memory - essentially a dynamic array. It's a generic type that wraps around a slice and manages automatic memory growth. [1](#0-0) 

## Importing ArrayList

ArrayList is part of the standard library:

```zig
const std = @import("std");
const ArrayList = std.ArrayList;
``` [2](#0-1) 

## Initialization

**Initialize an empty ArrayList:**

```zig
var list: ArrayList(i32) = .empty;
defer list.deinit(allocator);
``` [3](#0-2) 

**Initialize with pre-allocated capacity:**

```zig
var list = try ArrayList(i32).initCapacity(allocator, 100);
defer list.deinit(allocator);
``` [4](#0-3) 

## Core Operations

### Adding Elements

**Append a single element:**

```zig
try list.append(allocator, 42);
``` [5](#0-4) 

**Append multiple elements:**

```zig
try list.appendSlice(allocator, &[_]i32{ 1, 2, 3 });
``` [6](#0-5) 

**Append the same value multiple times:**

```zig
try list.appendNTimes(allocator, 0, 10);
``` [7](#0-6) 

**Insert at a specific index:**

```zig
try list.insert(allocator, 0, 5); // Insert at beginning
``` [8](#0-7) 

### Removing Elements

**Pop the last element:**

```zig
const value = list.pop(); // Returns ?T
``` [9](#0-8) 

**Remove by index (preserving order):**

```zig
const removed = list.orderedRemove(index);
```

This is O(N) because it shifts all elements after the removed one. [10](#0-9) 

**Remove by index (swap with last, O(1)):**

```zig
const removed = list.swapRemove(index);
```

This doesn't preserve order but is O(1). [11](#0-10) 

**Remove multiple indices:**

```zig
list.orderedRemoveMany(&[_]usize{ 0, 2, 5 }); // Indices must be sorted
``` [12](#0-11) 

## Accessing Elements

**Direct slice access:**

The `items` field provides direct access to the underlying slice:

```zig
for (list.items) |item| {
    std.debug.print("{}\n", .{item});
}
list.items[0] = 100; // Direct modification
``` [13](#0-12) 

**Get last element:**

```zig
const last = list.getLast(); // Asserts list is not empty
const maybe_last = list.getLastOrNull(); // Returns ?T
``` [14](#0-13) 

## Memory Management

**Deinitialize:**

Always call `deinit` when done to free memory:

```zig
list.deinit(allocator);
``` [15](#0-14) 

**Take ownership of the underlying slice:**

```zig
const owned = try list.toOwnedSlice(allocator);
defer allocator.free(owned);
// list is now empty and safe to deinit
``` [16](#0-15) 

**Resize:**

```zig
try list.resize(allocator, 50); // New elements are undefined
``` [17](#0-16) 

**Clear without freeing memory:**

```zig
list.clearRetainingCapacity();
``` [18](#0-17) 

**Clear and free memory:**

```zig
list.clearAndFree(allocator);
``` [19](#0-18) 

## Capacity Management

**Ensure capacity for additional items:**

```zig
try list.ensureUnusedCapacity(allocator, 100);
// Now can add 100 items without reallocation
``` [20](#0-19) 

**Ensure total capacity:**

```zig
try list.ensureTotalCapacity(allocator, 200);
```

This uses super-linear growth (grows by 1.5x plus a constant) for amortized O(1) append. [21](#0-20) [22](#0-21) 

## AssumeCapacity Variants

Many operations have `AssumeCapacity` variants that don't allocate and assert there's enough capacity. Use these after pre-allocating:

```zig
try list.ensureUnusedCapacity(allocator, 10);
list.appendAssumeCapacity(1);
list.appendSliceAssumeCapacity(&[_]i32{ 2, 3, 4 });
``` [23](#0-22) [24](#0-23) 

## Bounded Variants (New in 0.15)

The `Bounded` variants work without an allocator by using pre-allocated capacity, returning `error.OutOfMemory` if capacity is insufficient:

```zig
var buffer: [100]i32 = undefined;
var list = ArrayList(i32).initBuffer(&buffer);
try list.appendBounded(42); // No allocator needed!
``` [25](#0-24) [26](#0-25) 

## Advanced Operations

**Clone an ArrayList:**

```zig
var cloned = try list.clone(allocator);
defer cloned.deinit(allocator);
``` [27](#0-26) 

**Replace a range:**

```zig
try list.replaceRange(allocator, start, len, &new_items);
``` [28](#0-27) 

**Insert a slice:**

```zig
try list.insertSlice(allocator, index, &[_]i32{ 9, 8, 7 });
``` [29](#0-28) 

## Complete Example

Here's an idiomatic example combining common operations: [30](#0-29) 

## Notes

### Key Design Principles:

1. **Explicit Allocator Pattern**: Unlike some languages, you must pass an allocator to every operation that may allocate memory. This makes memory allocations explicit and visible.

2. **Two Variants**: There's also a deprecated `Managed` variant that stores the allocator in the struct. The current idiomatic approach is the unmanaged variant shown above where you pass the allocator to each method. [31](#0-30) 

3. **Direct Access**: The `items` field is meant to be accessed directly - it's not encapsulated behind getters/setters.

4. **Pointer Invalidation**: Operations that may reallocate (like `append`, `insert`) invalidate pointers to elements. Operations with `AssumeCapacity` never invalidate pointers.

5. **Growth Strategy**: Capacity grows super-linearly (approximately 1.5x) to provide amortized O(1) append operations.

6. **Zero-Sized Types**: ArrayList handles zero-sized types specially to avoid unnecessary allocations. [32](#0-31)

### Citations

**File:** lib/std/std.zig (L42-50)
```zig
/// A contiguous, growable list of items in memory. This is a wrapper around a
/// slice of `T` values.
///
/// The same allocator must be used throughout its entire lifetime. Initialize
/// directly with `empty` or `initCapacity`, and deinitialize with `deinit` or
/// `toOwnedSlice`.
pub fn ArrayList(comptime T: type) type {
    return array_list.Aligned(T, null);
}
```

**File:** lib/std/std.zig (L51-51)
```zig
pub const array_list = @import("array_list.zig");
```

**File:** lib/std/array_list.zig (L10-13)
```zig
/// Deprecated.
pub fn Managed(comptime T: type) type {
    return AlignedManaged(T, null);
}
```

**File:** lib/std/array_list.zig (L578-585)
```zig
        /// Contents of the list. This field is intended to be accessed
        /// directly.
        ///
        /// Pointers to elements in this slice are invalidated by various
        /// functions of this ArrayList in accordance with the respective
        /// documentation. In all cases, "invalidated" means that the memory
        /// has been passed to an allocator's resize or free function.
        items: Slice = &[_]T{},
```

**File:** lib/std/array_list.zig (L591-594)
```zig
        pub const empty: Self = .{
            .items = &.{},
            .capacity = 0,
        };
```

**File:** lib/std/array_list.zig (L602-609)
```zig
        /// Initialize with capacity to hold `num` elements.
        /// The resulting capacity will equal `num` exactly.
        /// Deinitialize with `deinit` or use `toOwnedSlice`.
        pub fn initCapacity(gpa: Allocator, num: usize) Allocator.Error!Self {
            var self = Self{};
            try self.ensureTotalCapacityPrecise(gpa, num);
            return self;
        }
```

**File:** lib/std/array_list.zig (L616-621)
```zig
        pub fn initBuffer(buffer: Slice) Self {
            return .{
                .items = buffer[0..0],
                .capacity = buffer.len,
            };
        }
```

**File:** lib/std/array_list.zig (L624-627)
```zig
        pub fn deinit(self: *Self, gpa: Allocator) void {
            gpa.free(self.allocatedSlice());
            self.* = undefined;
        }
```

**File:** lib/std/array_list.zig (L655-666)
```zig
        pub fn toOwnedSlice(self: *Self, gpa: Allocator) Allocator.Error!Slice {
            const old_memory = self.allocatedSlice();
            if (gpa.remap(old_memory, self.items.len)) |new_items| {
                self.* = .empty;
                return new_items;
            }

            const new_memory = try gpa.alignedAlloc(T, alignment, self.items.len);
            @memcpy(new_memory, self.items);
            self.clearAndFree(gpa);
            return new_memory;
        }
```

**File:** lib/std/array_list.zig (L679-683)
```zig
        pub fn clone(self: Self, gpa: Allocator) Allocator.Error!Self {
            var cloned = try Self.initCapacity(gpa, self.capacity);
            cloned.appendSliceAssumeCapacity(self.items);
            return cloned;
        }
```

**File:** lib/std/array_list.zig (L690-693)
```zig
        pub fn insert(self: *Self, gpa: Allocator, i: usize, item: T) Allocator.Error!void {
            const dst = try self.addManyAt(gpa, i, 1);
            dst[0] = item;
        }
```

**File:** lib/std/array_list.zig (L788-800)
```zig
        pub fn insertSlice(
            self: *Self,
            gpa: Allocator,
            index: usize,
            items: []const T,
        ) Allocator.Error!void {
            const dst = try self.addManyAt(
                gpa,
                index,
                items.len,
            );
            @memcpy(dst, items);
        }
```

**File:** lib/std/array_list.zig (L834-851)
```zig
        pub fn replaceRange(
            self: *Self,
            gpa: Allocator,
            start: usize,
            len: usize,
            new_items: []const T,
        ) Allocator.Error!void {
            const after_range = start + len;
            const range = self.items[start..after_range];
            if (range.len < new_items.len) {
                const first = new_items[0..range.len];
                const rest = new_items[range.len..];
                @memcpy(range[0..first.len], first);
                try self.insertSlice(gpa, after_range, rest);
            } else {
                self.replaceRangeAssumeCapacity(start, len, new_items);
            }
        }
```

**File:** lib/std/array_list.zig (L893-896)
```zig
        pub fn append(self: *Self, gpa: Allocator, item: T) Allocator.Error!void {
            const new_item_ptr = try self.addOne(gpa);
            new_item_ptr.* = item;
        }
```

**File:** lib/std/array_list.zig (L903-905)
```zig
        pub fn appendAssumeCapacity(self: *Self, item: T) void {
            self.addOneAssumeCapacity().* = item;
        }
```

**File:** lib/std/array_list.zig (L913-916)
```zig
        pub fn appendBounded(self: *Self, item: T) error{OutOfMemory}!void {
            if (self.capacity - self.items.len == 0) return error.OutOfMemory;
            return appendAssumeCapacity(self, item);
        }
```

**File:** lib/std/array_list.zig (L922-926)
```zig
        pub fn orderedRemove(self: *Self, i: usize) T {
            const old_item = self.items[i];
            self.replaceRangeAssumeCapacity(i, 1, &.{});
            return old_item;
        }
```

**File:** lib/std/array_list.zig (L940-955)
```zig
        pub fn orderedRemoveMany(self: *Self, sorted_indexes: []const usize) void {
            if (sorted_indexes.len == 0) return;
            var shift: usize = 1;
            for (sorted_indexes[0 .. sorted_indexes.len - 1], sorted_indexes[1..]) |removed, end| {
                if (removed == end) continue; // allows duplicates in `sorted_indexes`
                const start = removed + 1;
                const len = end - start; // safety checks `sorted_indexes` are sorted
                @memmove(self.items[start - shift ..][0..len], self.items[start..][0..len]); // safety checks initial `sorted_indexes` are in range
                shift += 1;
            }
            const start = sorted_indexes[sorted_indexes.len - 1] + 1;
            const end = self.items.len;
            const len = end - start; // safety checks final `sorted_indexes` are in range
            @memmove(self.items[start - shift ..][0..len], self.items[start..][0..len]);
            self.items.len = end - shift;
        }
```

**File:** lib/std/array_list.zig (L962-968)
```zig
        pub fn swapRemove(self: *Self, i: usize) T {
            const val = self.items[i];
            self.items[i] = self.items[self.items.len - 1];
            self.items[self.items.len - 1] = undefined;
            self.items.len -= 1;
            return val;
        }
```

**File:** lib/std/array_list.zig (L973-976)
```zig
        pub fn appendSlice(self: *Self, gpa: Allocator, items: []const T) Allocator.Error!void {
            try self.ensureUnusedCapacity(gpa, items.len);
            self.appendSliceAssumeCapacity(items);
        }
```

**File:** lib/std/array_list.zig (L981-987)
```zig
        pub fn appendSliceAssumeCapacity(self: *Self, items: []const T) void {
            const old_len = self.items.len;
            const new_len = old_len + items.len;
            assert(new_len <= self.capacity);
            self.items.len = new_len;
            @memcpy(self.items[old_len..][0..items.len], items);
        }
```

**File:** lib/std/array_list.zig (L1061-1065)
```zig
        pub inline fn appendNTimes(self: *Self, gpa: Allocator, value: T, n: usize) Allocator.Error!void {
            const old_len = self.items.len;
            try self.resize(gpa, try addOrOom(old_len, n));
            @memset(self.items[old_len..self.items.len], value);
        }
```

**File:** lib/std/array_list.zig (L1101-1104)
```zig
        pub fn resize(self: *Self, gpa: Allocator, new_len: usize) Allocator.Error!void {
            try self.ensureTotalCapacity(gpa, new_len);
            self.items.len = new_len;
        }
```

**File:** lib/std/array_list.zig (L1150-1153)
```zig
        pub fn clearRetainingCapacity(self: *Self) void {
            @memset(self.items, undefined);
            self.items.len = 0;
        }
```

**File:** lib/std/array_list.zig (L1156-1160)
```zig
        pub fn clearAndFree(self: *Self, gpa: Allocator) void {
            gpa.free(self.allocatedSlice());
            self.items.len = 0;
            self.capacity = 0;
        }
```

**File:** lib/std/array_list.zig (L1165-1168)
```zig
        pub fn ensureTotalCapacity(self: *Self, gpa: Allocator, new_capacity: usize) Allocator.Error!void {
            if (self.capacity >= new_capacity) return;
            return self.ensureTotalCapacityPrecise(gpa, growCapacity(new_capacity));
        }
```

**File:** lib/std/array_list.zig (L1174-1177)
```zig
            if (@sizeOf(T) == 0) {
                self.capacity = math.maxInt(usize);
                return;
            }
```

**File:** lib/std/array_list.zig (L1201-1207)
```zig
        pub fn ensureUnusedCapacity(
            self: *Self,
            gpa: Allocator,
            additional_count: usize,
        ) Allocator.Error!void {
            return self.ensureTotalCapacity(gpa, try addOrOom(self.items.len, additional_count));
        }
```

**File:** lib/std/array_list.zig (L1331-1337)
```zig
        pub fn pop(self: *Self) ?T {
            if (self.items.len == 0) return null;
            const val = self.items[self.items.len - 1];
            self.items[self.items.len - 1] = undefined;
            self.items.len -= 1;
            return val;
        }
```

**File:** lib/std/array_list.zig (L1353-1364)
```zig
        /// Return the last element from the list.
        /// Asserts that the list is not empty.
        pub fn getLast(self: Self) T {
            return self.items[self.items.len - 1];
        }

        /// Return the last element from the list, or
        /// return `null` if list is empty.
        pub fn getLastOrNull(self: Self) ?T {
            if (self.items.len == 0) return null;
            return self.getLast();
        }
```

**File:** lib/std/array_list.zig (L1370-1372)
```zig
        pub fn growCapacity(minimum: usize) usize {
            return minimum +| (minimum / 2 + init_capacity);
        }
```

**File:** lib/std/array_list.zig (L1510-1558)
```zig
        var list: ArrayList(i32) = .empty;
        defer list.deinit(a);

        {
            var i: usize = 0;
            while (i < 10) : (i += 1) {
                list.append(a, @as(i32, @intCast(i + 1))) catch unreachable;
            }
        }

        {
            var i: usize = 0;
            while (i < 10) : (i += 1) {
                try testing.expect(list.items[i] == @as(i32, @intCast(i + 1)));
            }
        }

        for (list.items, 0..) |v, i| {
            try testing.expect(v == @as(i32, @intCast(i + 1)));
        }

        try testing.expect(list.pop() == 10);
        try testing.expect(list.items.len == 9);

        list.appendSlice(a, &[_]i32{ 1, 2, 3 }) catch unreachable;
        try testing.expect(list.items.len == 12);
        try testing.expect(list.pop() == 3);
        try testing.expect(list.pop() == 2);
        try testing.expect(list.pop() == 1);
        try testing.expect(list.items.len == 9);

        var unaligned: [3]i32 align(1) = [_]i32{ 4, 5, 6 };
        list.appendUnalignedSlice(a, &unaligned) catch unreachable;
        try testing.expect(list.items.len == 12);
        try testing.expect(list.pop() == 6);
        try testing.expect(list.pop() == 5);
        try testing.expect(list.pop() == 4);
        try testing.expect(list.items.len == 9);

        list.appendSlice(a, &[_]i32{}) catch unreachable;
        try testing.expect(list.items.len == 9);

        // can only set on indices < self.items.len
        list.items[7] = 33;
        list.items[8] = 42;

        try testing.expect(list.pop() == 42);
        try testing.expect(list.pop() == 33);
    }
```
