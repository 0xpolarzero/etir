# Spec 08 – Build, Tests, CI, Corpus, and Security

## 1. Scope

This spec covers:

- `build.zig` and any `build/*.zig` helpers for building:
  - The C ABI shared library.
  - The Node‑API addon.
  - The NativeAOT comparer binary (as a build dependency or prebuilt).
- Test infrastructure:
  - Zig unit and e2e tests.
  - JS/Vitest tests.
- Verification corpus and oracles.
- Security, robustness, and practical notes from the full plan.

Primary files:

- `build.zig`, `build/*.zig`
- `tests/corpus/*`, inline Zig tests under `src/**/*.zig`, `tests/e2e/*`
- `.github/workflows/*` (or `CI/github-actions.yml`)

## 2. Repo & agent guidelines (local rules)

General:

- Build recipes should keep `build.zig` as a thin router; heavy logic goes into `build/*.zig`.
- Commands:
  - `zig build` – compiles static/shared libs and addon.
  - `zig build node` – builds Node‑API addon only.
  - `zig build package` – builds/stages the full Node package.
  - `zig build test` – runs Zig inline tests and Vitest.
  - `zig build lint` / `zig build fmt` – runs Zig formatter and Biome.
  - `zig build all` – chains build/package/lint/test.

Concurrency / agent coordination:

- Build/test specs touch global configuration; coordinate changes with all tracks.
- Do not restore or overwrite build files wholesale; evolve them incrementally.
- Keep CI configuration minimal and focused; avoid accidental coupling to local paths.

## 3. Dependencies & parallelization

Dependencies:

- Build scripts depend on:
  - C ABI target (Spec 01).
  - Node addon target (Spec 07).
  - NativeAOT comparer (Spec 06).
- Tests depend on:
  - Primitives (Spec 02).
  - ETIR pipeline (Spec 03).
  - Write‑back (Spec 04).
  - Instructions pack (Spec 05).

Parallelization:

- You can scaffold build targets and CI early, while core modules are still stubs, as long as:
  - The target names and paths match the plan.
  - Tests are enabled gradually as features land.
- Corpus creation and oracle definitions can proceed in parallel with all other specs.

## 4. Implementation tasks (ordered)

1. Build configuration:
   - In `build.zig` and `build/*.zig`, define:
     - Shared library target `etir` from `src/lib_c.zig`.
     - Node‑API addon target `etir` from `src/lib_node.zig`, installed to `zig-out/lib/node/etir.node`.
     - Optional integration with NativeAOT comparer binaries (e.g., staging them beside the addon).
2. Composite build steps:
   - Implement:
     - `zig build node`
     - `zig build package`
     - `zig build test`
     - `zig build lint` / `zig build fmt`
     - `zig build all`
3. Corpus:
   - Populate `tests/corpus/` with DOCX fixtures covering:
     - Emoji and complex scripts.
     - Tabs, line breaks, soft and no‑break hyphens.
     - Hyperlinks, bookmarks, and comment ranges.
     - Footnotes/endnotes with cross‑refs.
     - Tables (including nested and merged cells).
     - Modern and legacy text boxes.
     - Headers/footers with fields.
4. Oracles and e2e tests:
   - Define e2e tests under `tests/e2e/` that:
     - Call ETIR extraction, write‑back, and compare.
     - Validate outputs using JSON Schemas and manual/automated checks.
5. JS tests:
   - Use Vitest specs under `bindings/js/src/*.spec.ts` to:
     - Verify JS `Etir` class behavior.
     - Ensure error propagation from native layer.
6. CI configuration:
   - Implement a GitHub Actions workflow (or similar) that:
     - Builds on a matrix of OS/architectures, at least for core targets.
     - Runs `zig build all`.
     - Optionally checks that outputs open in Word without repair (on Windows) using COM automation.
7. Security and robustness:
   - Add configuration flags or runtime checks to enforce:
     - ZIP bomb protections (entry count, size limits).
     - XML entity expansion protections.
     - Memory limits for streaming.

## 5. Extract from full implementation plan

### 5.1 Build.zig highlights

From §13 of the full plan (truncated; adjust as needed):

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "etir",
        .root_source_file = .{ .path = "src/lib_c.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.install();

    const node = b.addSharedLibrary(.{
        .name = "etir",
        .root_source_file = .{ .path = "src/lib_node.zig" },
        .target = target,
        .optimize = optimize,
    });
    node.linkLibC();
    node.installArtifact(); // stage to zig-out/lib/node/etir.node
}
```

> *Expose two artifacts:*  
>  
> 1. **C ABI** shared library exporting the five functions (for general embedders),  
> 2. **Node‑API** addon (`etir.node`) linking the same C ABI internally.  
>  
> *Add build options for locating the NativeAOT comparer next to the addon and `dlopen` it at runtime (on Windows load via `LoadLibrary`).*

### 5.2 Verification corpus & oracles

From §14 of the full plan:

> Ship fixtures that exercise:  
>  
> * emoji, complex scripts (Arabic/Hebrew), mixed LTR/RTL  
> * tabs, line breaks, soft/no‑break hyphens  
> * hyperlinks wrapping partial phrases  
> * dense bookmarks + comment ranges (plus large `/word/comments.xml`)  
> * footnotes/endnotes with cross‑refs  
> * tables including **nested tables** and merged cells  
> * text boxes: modern (`wps:txbx`) and legacy (`v:textbox`)  
> * headers/footers with PAGE fields  
> * fields: TOC/REF/PAGE — edits to **results** only  
>  
> **Oracles**  
>  
> 1. All outputs open in Word *without repair*.  
> 2. Reviewers verify redlines match intent.  
> 3. On Windows CI, optionally compare a subset via Word COM `Document.Compare` to document differences (legal numbering, etc.).  
> 4. Determinism: with fixed author/date, `compare` yields byte‑stable results for identical inputs.

### 5.3 Security & robustness

From §15 of the full plan:

> * **ZIP bombs**: limit total expanded size, entry count, recursion. Reject paths with `..` or absolute roots. Enforce per‑entry size caps.  
> * **XML entity expansion**: OOXML doesn’t use external entities; nonetheless disable any DTD or external entity resolution in the parser.  
> * **Time‑bomb footers**: calculate `fileHash` from *story parts only* to avoid volatile docProps changing fingerprints spuriously.  
> * **Memory**: stream SAX parsing; avoid materializing whole parts when possible; reuse buffers.  
> * **Parallelism**: expose a worker pool for compare if your host wants it (compare is CPU‑heavy).  
> * **Logging**: file names, sizes, timings; never content.

### 5.4 Practical notes & edge cases

From §16 of the full plan:

> * **`w:sym`**: If you can’t reliably map certain fonts (e.g., Wingdings/Webdings) to Unicode, serialize them as `{sym font="Wingdings" char="F03C"}` and mark the span protected to avoid LLM “fixing” them.  
> * **`w:t` `xml:space`**: honor `preserve`; when writing back, if leading/trailing spaces exist, set `xml:space="preserve"` on that `w:t`.  
> * **Bookmarks/comments**: they are element *ranges* with IDs; ETIR encodes them as zero‑width anchors (`Start/End`) at cluster offsets. Don’t reorder; enforce proper nesting.  
> * **Headers/footers**: comparer handles them; UI display in Word may highlight differently but markup is correct.  
> * **Math (`m:oMath`)**: surface `{math}` tokens as protected or ignore; never split.  
> * **Revisions in inputs**: ETIR defaults to *flattened* view (include insertions, drop deletions) to avoid “diff of a diff”. Provide a reader flag later if “preserve revisions” is needed.

### 5.5 Example end‑to‑end (tiny)

From §17 of the full plan:

```json
{
  "part":"word/document.xml",
  "kind":"paragraph",
  "pid":"8B12",
  "text":"The Company will issue\u00A0Shares.\nSee Note 1.\t{sym font=\"Symbol\" char=\"F070\"}",
  "anchors":[
    {"type":"footnoteRef","id":"1","at":28}
  ],
  "protectedZones":[
    {"type":"fieldInstr","range":[4,17]},
    {"type":"hyperlinkBoundary","at":35}
  ]
}
```

> **From ETIR → after.docx rules applied**:  
>  
> * The visible text changes only inside editable segments.  
> * `footnoteRef` at cluster 28 is preserved exactly.  
> * A hyperlink boundary at 35 is not crossed.
