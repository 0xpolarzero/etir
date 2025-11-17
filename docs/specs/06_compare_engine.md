# Spec 06 – Compare Engine (NativeAOT + Zig Wrapper)

## 1. Scope

This spec covers the implementation of the DOCX compare engine and its Zig wrapper:

- A .NET 8 NativeAOT binary that wraps OpenXmlPowerTools’ `WmlComparer`.
- A Zig module that FFI‑calls the NativeAOT export and maps results into the internal error model.
- The `etir_docx_compare` C ABI export wired to the Zig wrapper.

Primary files:

- `native/comparer/EtirComparer.csproj`
- `native/comparer/Program.cs`
- `src/compare.zig`
- `src/lib_c.zig` (for the `etir_docx_compare` export, Spec 01‑owned)

## 2. Repo & agent guidelines (local rules)

General rules:

- .NET project should be self‑contained under `native/comparer/`.
- Do not commit built binaries; CI and `zig build` should produce them.
- Zig wrapper should:
  - Use `extern` declarations for the NativeAOT function.
  - Map non‑zero return codes into `errors.Code.COMPARE_FAILED`.

Concurrency / agent coordination:

- Treat `src/lib_c.zig` as owned by Spec 01; in this spec, only change the call site for `compare_mod.run` if necessary.
- Do not change public C ABI signatures in this spec; if ABI must change, coordinate through Spec 01.
- NativeAOT artifacts will be discovered by build scripts (Spec 08); do not hard‑code paths outside of build configuration.

## 3. Dependencies & parallelization

Dependencies:

- Does not depend on ETIR extraction or write‑back.
- Depends only on:
  - Spec 01 for error codes and `etir_docx_compare` C ABI signature.

Parallelization:

- This spec can run fully in parallel with all others (Specs 02–05, 07–08).
- It should be completed early, since `compare` is the bedrock for Track Changes outputs.

## 4. Implementation tasks (ordered)

1. NativeAOT comparer:
   - Create `native/comparer/EtirComparer.csproj` targeting .NET 8 with NativeAOT.
   - Implement `Program.cs` (or `Entry.cs`) with:
     - `UnmanagedCallersOnly(EntryPoint = "docx_compare")`.
     - UTF‑8 path decoding via `Marshal.PtrToStringUTF8`.
     - Construction of `WmlDocument` for before/after.
     - Configuration of `WmlComparerSettings` (author, optional date).
     - Call to `WmlComparer.Compare` and saving to output path.
     - Non‑zero return value on error.
   - Configure RID matrix build: `win-x64`, `linux-x64`, `linux-arm64`, `osx-arm64`.
2. Zig compare wrapper (`src/compare.zig`):
   - Declare `extern fn docx_compare(...) callconv(.C) c_int;`.
   - Implement `run(before, after, out, author, date_iso)` returning `union(enum) { ok, err: { code, msg } }`.
   - Perform basic existence checks for `before` and `after` paths; map to `OPEN_FAILED_BEFORE` / `OPEN_FAILED_AFTER`.
   - Call `docx_compare`; map non‑zero return to `COMPARE_FAILED` with a generic message.
3. C ABI integration:
   - Confirm `src/lib_c.zig`’s `etir_docx_compare` calls `compare_mod.run` and propagates errors via `last_error`.
4. Tests:
   - Add Zig tests (or external scripts) that:
     - Run the comparer on known simple DOCX pairs.
     - Validate that outputs open in Word without repair (manually or via later CI).

## 5. Extract from full implementation plan

### 5.1 NativeAOT .NET comparer (single exported symbol)

From §5 of the full plan:

```csharp
using System;
using System.Globalization;
using System.Runtime.InteropServices;
using DocumentFormat.OpenXml.Packaging; // for sanity checks if desired
using OpenXmlPowerTools;               // WmlDocument, WmlComparer, settings

public static class Entry
{
    [UnmanagedCallersOnly(EntryPoint = "docx_compare")]
    public static int DocxCompare(
        nint beforePathUtf8, nint afterPathUtf8, nint reviewOutPathUtf8,
        nint authorUtf8, nint dateIsoUtf8 /* nullable */
    )
    {
        try
        {
            string Before() => Marshal.PtrToStringUTF8(beforePathUtf8)!;
            string After()  => Marshal.PtrToStringUTF8(afterPathUtf8)!;
            string Out()    => Marshal.PtrToStringUTF8(reviewOutPathUtf8)!;
            string Author() => Marshal.PtrToStringUTF8(authorUtf8)!;
            string? Date()  => dateIsoUtf8 == 0 ? null : Marshal.PtrToStringUTF8(dateIsoUtf8);

            var before = new WmlDocument(Before());
            var after  = new WmlDocument(After());

            var settings = new WmlComparerSettings
            {
                AuthorForRevisions = Author(),
                DebugTempFileDiags = false,
            };
            if (Date() is string d)
            {
                if (DateTimeOffset.TryParse(d, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dto))
                    settings.DateTimeForRevisions = dto.UtcDateTime;
            }

            var compared = WmlComparer.Compare(before, after, settings);
            compared.SaveAs(Out());
            return 0;
        }
        catch
        {
            // Zig's wrapper turns non-zero into COMPARE_FAILED and supplies a generic message.
            return 1;
        }
    }
}
```

> Build RID matrix: `win-x64`, `linux-x64`, `linux-arm64`, `osx-arm64`. Stage the produced `docx_compare.{dll,so,dylib}` beside `etir.node` or the Zig `.so/.dll` for dlopen.

### 5.2 Compare wrapper (Zig → NativeAOT)

From §6 of the full plan:

```zig
const std = @import("std");
const errors = @import("errors.zig");

extern fn docx_compare(
    before_path: [*:0]const u8,
    after_path:  [*:0]const u8,
    out_path:    [*:0]const u8,
    author:      [*:0]const u8,
    date_iso:    ?[*:0]const u8,
) callconv(.C) c_int;

pub fn run(before: []const u8, after: []const u8, out: []const u8, author: []const u8, date_iso: ?[]const u8) union(enum) {
    ok, err: struct { code: errors.Code, msg: []const u8 }
} {
    // Basic existence checks; you can also perform shallow DOCX checks here
    if (!fileExists(before)) return .{ .err = .{ .code = .OPEN_FAILED_BEFORE, .msg = "before docx not found" } };
    if (!fileExists(after))  return .{ .err = .{ .code = .OPEN_FAILED_AFTER,  .msg = "after docx not found" } };

    const rc = docx_compare(
        toZ(before), toZ(after), toZ(out), toZ(author),
        if (date_iso) |d| toZ(d) else null
    );
    if (rc != 0) return .{ .err = .{ .code = .COMPARE_FAILED, .msg = "docx compare failed" } };
    return .ok;

    fn fileExists(p: []const u8) bool { return std.fs.cwd().access(p, .{}) == .success; }
    fn toZ(s: []const u8) [*:0]const u8 { return @ptrCast([*:0]const u8, s.ptr); }
}
```

