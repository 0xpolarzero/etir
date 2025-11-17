You are an expert engineering planner for a hybrid Zig + NativeAOT .NET + Node.js project. You’ve been given docs/specs.md (pasted below) which defines the ETIR DOCX library: `toEtir`, `fromEtir`, `compare`, `getInstructions`, Zig exports, Node-API bindings, NativeAOT compare bridge, ETIR/SourceMap/Instructions JSON models, error codes, verification corpus, and performance/ops constraints.

Task: produce a comprehensive, reviewable execution plan that turns the spec into working software. For each step:

1. Describe the objective and success criteria in concrete terms.
2. List all implementation tasks, dependencies, and responsible subsystems (Zig core, NativeAOT compare engine, JS bindings, docs/tests).
3. Provide explicit test coverage requirements, including sample DOCX fixtures, ETIR JSON snippets, and CLI/API invocations. Include exact commands (e.g., `zig build node`, `zig build test`, `npm --prefix bindings/js run lint`) and expected observable outcomes.
4. Call out risks, validation hooks, and observability/logging to add at that stage.
5. Identify which steps can run in parallel and why; note any blocking artifacts (interfaces, schemas, binaries) that must be delivered first.
6. Keep steps small enough for code review (1–3 days of work) and name them with a short tag (e.g., “ETIR-Extraction-Core”).
7. End with a consolidated checklist that sequences the steps and flags parallel tracks.

Expectations:
- Use the language and constraints in docs/specs.md literally (error codes, anchor handling, fingerprinting, WmlComparer usage, NativeAOT targets, etc.).
- Assume a fresh repo matching the structure in AGENTS instructions: Zig sources in `src/`, build scripts in `build/*.zig`, JS bindings under `bindings/js/`.
- Include Windows-specific validation where the spec demands it (Word Compare sanity checks).
- Reference every artifact by path (e.g., `src/lib_node.zig`, `build/lib.zig`, `bindings/js/src/index.ts`).
- Provide enough detail that an engineer could start work without clarification.

Paste docs/specs.md after this prompt so the planner can cite exact requirements.

---

# Repository Guidelines (AGENTS.md)

# Repository Guidelines

## Project Structure & Module Organization
Zig sources live in `src/` (core logic, C ABI exports, N-API glue). Build recipes live in `build/*.zig`, keeping `build.zig` a thin router. JS/TS code sits in `bindings/js/` with outputs under `bindings/js/dist/`. Tests stay inline: Zig checks in `.zig` files and Vitest specs in `bindings/js/src/*.spec.ts`.

## Build, Test & Development Commands
- `zig build` – compiles static/shared libs and addon; use `zig build node` or `zig build package` when you only need the N-API artifact or the full staged package.
- `zig build test` – runs Zig inline tests plus Vitest through the bindings workspace.
- `zig build lint` / `zig build fmt` – runs `zig fmt` + Biome; `zig build all` chains build/package/lint/test.
- `npm --prefix bindings/js install|run <script>` – talk directly to bindings tooling during JS/TS-only work.

## Coding Style & Naming Conventions
Run `zig fmt` before committing; Zig files stay in snake_case modules with exported symbols prefixed `etir_` to keep the ABI stable. TypeScript uses Biome (configured in `bindings/js/biome.json`) with 2-space indentation, 100-character lines, and single quotes. Prefer descriptive module names (`internal/math.zig`) and keep Node-facing filenames aligned with their Zig counterpart (e.g., `lib_node.zig` ⇄ `bindings/js/src/index.ts`).

## Testing Guidelines
Each feature needs inline Zig tests plus Vitest coverage of the staged addon. Name JS tests `<module>.spec.ts` and keep them colocated with the source. If `zig build test` fails because the addon is missing, run `zig build package` so Vitest can load the staged `.node`.

## Commit & Pull Request Guidelines
Follow Conventional Commits (`feat:`, `fix:`, `chore:`) as in `feat: initialize etir with Zig core + Node bindings`. Scope commits tightly and call out the subsystem (`feat(node): expose checksum`). Pull requests should summarize intent, link issues, and paste the most recent `zig build test` + `zig build lint` output; attach screenshots or logs for any developer-facing UX change.

## Security & Configuration Tips
Ensure Zig 0.15.2 and Node 24.x are installed; mismatches break the addon ABI. Windows developers should set `NODE_ADDON_IMPORT_LIB` if `node.lib` is non-standard. Override `ETIR_NATIVE_PATH` to point at the freshly built `.node` in `zig-out/lib/node` when debugging. Run `zig build clean` before releases so cached artifacts do not leak across platforms.

## Agent Operations
Automation or AI assistants must never run `git push` and must not commit unless a maintainer explicitly asks. Keep work uncommitted, leave history untouched, and never consider a task finished until `zig build all` passes locally.

---

# Full Specification (docs/specs.md)

Below is a **research‑grade, end‑to‑end specification** for a DOCX library you’ll ship in **Zig** (with **JavaScript bindings**) that exposes the four entry points you requested:

* `toEtir` (DOCX → Editable Text IR + source map)
* `fromEtir` (ETIR → “after.docx” — no revisions)
* `compare` (before.docx, after.docx → review.docx with **real Track Changes**)
* `getInstructions` (LLM‑ready guidance/metadata for working with ETIR safely)

It includes: goals & guarantees, hard limits (honest contract), the public API, wire‑level data models, coverage of the WordprocessingML content that matters, implementation guidance for Zig + a **C FFI + NativeAOT** engine, error codes, performance/security guidance, and a thorough verification plan with **primary references**.

---

## 0) Short explanation (what this library is for)

**Goal**: let the etir library (or any integrator embedding it) hand an **existing DOCX** to an LLM for text edits **without losing fidelity**, then return a **reviewable, native redline** (Word “Track Changes”). We accomplish this by:

1. exposing a **lossless, text‑only ETIR** representation (for AI to edit),
2. **re‑materializing** those edits into a *clean* “after.docx” (we only replace visible text), and
3. using a **proven DOCX comparer** to generate a third DOCX with **true revision markup** (`w:ins`/`w:del`), the same format Word, OnlyOffice, and Collabora understand.

> **Key design choice**: we **don’t** hand‑author the revision XML; we delegate that to **WmlComparer** (Open‑Xml PowerTools) which compares DOCX↔DOCX and produces a tracked‑changes DOCX. Recent builds explicitly support **nested tables** and **text boxes**, two historically tricky zones.

---

## 1) Guarantees and honest limits

* **You will get a valid DOCX with real Track Changes** for *any* two valid input DOCX files via `compare`. That’s why `compare` is the **bedrock** endpoint for “any kind of content.”
* `toEtir`/`fromEtir` intentionally scope to **visible text**; they **do not** restructure tables, fields, numbering, shapes, or math. This keeps write‑back safe and fast.
* In some niche cases the redline produced by WmlComparer may **differ slightly from Word’s own Compare** (e.g., certain “legal numbering” alignments). If a client needs bit‑for‑bit parity with Word, expose an optional `engine="word"` (Windows‑only COM call to `Document.Compare`) as an alternate comparer.

---

## 2) Public API (Zig + JS)

We implement a small native lib in Zig that calls a **NativeAOT .NET** engine (C ABI) for the heavy compare. The **same** Zig package exposes ETIR endpoints (pure Zig/C) so the overall surface is:

### Zig signatures (exported)

```zig
// 1) DOCX → ETIR (+ sourcemap fingerprint)
pub export fn etir_docx_to_etir(
  docx_path: [*:0]const u8,
  etir_out_json_path: [*:0]const u8,   // writes ETIR JSON to disk
  map_out_json_path:  [*:0]const u8    // writes SourceMap bundle to disk
) c_int;

// 2) ETIR → after.docx (no revisions)
pub export fn etir_docx_from_etir(
  base_docx_path: [*:0]const u8,
  etir_json_path: [*:0]const u8,
  after_docx_out_path: [*:0]const u8,
  strict_anchors: bool
) c_int;

// 3) before+after → review.docx with Track Changes
pub export fn etir_docx_compare(
  before_docx_path: [*:0]const u8,
  after_docx_path:  [*:0]const u8,
  review_docx_out_path: [*:0]const u8,
  author_utf8: [*:0]const u8,          // "etir"
  date_iso_utc_or_null: ?[*:0]const u8 // "2025-11-16T14:00:00Z" or null
) c_int;

// 4) Instructions pack for LLMs
pub export fn etir_docx_get_instructions(
  etir_json_path: [*:0]const u8,
  instructions_out_json_path: [*:0]const u8
) c_int;

// Optional: retrieve last error string
pub export fn etir_docx_last_error() [*:0]const u8;
```

> `etir_docx_last_error` exists purely for host bindings to retrieve an explanatory message after a failed call. High-level consumers (e.g., the JS `Etir` class below) must throw errors directly and never expose this poll-style API.

### JavaScript binding (Node-API addon)

`zig build node` (or `zig build package`) emits `etir.node` via the Zig `lib_node.zig` N-API module. The bindings workspace simply loads that artifact (respecting `ETIR_NATIVE_PATH`) and exposes a state-first `Etir` helper so downstream apps get an OO API **and** real JS errors instead of polling `lastError()`:

```ts
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));
const requireNative = createRequire(import.meta.url);

function resolveEtirNative() {
  const override = process.env.ETIR_NATIVE_PATH;
  if (override && fs.existsSync(override)) return override;

  const staged = path.resolve(MODULE_DIR, '../dist/native/etir.node');
  if (fs.existsSync(staged)) return staged;

  const local = path.resolve(MODULE_DIR, '../../zig-out/lib/node/etir.node');
  if (fs.existsSync(local)) return local;

  throw new Error('Unable to locate etir.node; run `zig build package` first.');
}

const addon = requireNative(resolveEtirNative());

class DocxError extends Error {
  constructor(code: string, message: string) {
    super(message);
    this.name = `DocxError:${code}`;
  }
}

type Docx = Uint8Array & { readonly __kind: 'docx' };

export function makeDocx(bytes: Uint8Array): Docx {
  return Object.assign(new Uint8Array(bytes), { __kind: 'docx' as const });
}

interface CompareOptions {
  author?: string;
  dateISO?: string | null;
}

export class Etir {
  readonly document: Docx;
  readonly ir: string;
  readonly sourceMap: EtirSourceMap;
  readonly fingerprint: Fingerprint;

  constructor(document: Docx, private readonly compareDefaults: CompareOptions = {}) {
    this.document = document;
    const { ir, sourceMap } = this.#deriveEtir();
    this.ir = ir;
    this.sourceMap = sourceMap;
    this.fingerprint = this.#extractFingerprint(ir);
  }

  getIr(): string {
    return this.ir;
  }

  getSourceMap(): EtirSourceMap {
    return this.sourceMap;
  }

  getDocument(): Docx {
    return this.document;
  }

  toReviewDocxFrom(beforeDoc: Docx, opts: CompareOptions = {}): Uint8Array {
    this.#verifyFingerprint(this.document);
    return this.#compare(beforeDoc, this.document, opts);
  }

  toReviewDocxTo(afterDoc: Docx, opts: CompareOptions = {}): Uint8Array {
    this.#verifyFingerprint(this.document);
    return this.#compare(this.document, afterDoc, opts);
  }

  getInstructions(): InstructionsPack {
    return buildInstructions(this.ir);
  }

  #deriveEtir(): { ir: string; sourceMap: EtirSourceMap } {
    // Streams the document bytes through addon.etir_docx_to_etir and captures the ETIR + SourceMap payloads entirely in memory.
  }

  #extractFingerprint(ir: string): Fingerprint {
    // Parses the ETIR JSON `fingerprint` block (fileHash, storyHashes, pidIndex) into the internal Fingerprint struct.
  }

  #compare(before: Docx, after: Docx, opts: CompareOptions): Uint8Array {
    const author = opts.author ?? this.compareDefaults.author ?? 'etir';
    const dateISO = opts.dateISO ?? this.compareDefaults.dateISO ?? null;
    // Invokes addon.etir_docx_compare on the supplied DOCX buffers (internally marshalled via temp files/pipes) and returns the review DOCX bytes.
  }

  #verifyFingerprint(candidate: Docx): void {
    // Hash check against the cached `fingerprint.fileHash` to ensure the stored document still matches the ETIR payload.
  }

  #call(invoke: () => number): void {
    const code = invoke();
    if (code === 0) return;
    const message = addon.etir_docx_last_error();
    throw new DocxError(`E${code}`, message ?? 'etir native error');
  }
}

export function createEtir(bytes: Uint8Array, opts?: CompareOptions): Etir {
  return new Etir(makeDocx(bytes), opts);
}
```

* The constructor captures the ETIR payload, source map, and fingerprint once from the provided `Docx`, then treats `document` as immutable baseline state.
* `toReviewDocxFrom(beforeDoc)` always compares the supplied `Docx` (treated as “before”) to the stored `document` (“after”), while `toReviewDocxTo(afterDoc)` does the inverse; both require an explicit argument so the API stays symmetric and obvious.
* Private helpers `#extractFingerprint` and `#verifyFingerprint` keep the cached fingerprint in sync with ETIR content and guard every compare against the recorded baseline hash.
* `addon.etir_docx_last_error()` stays internal to the class; callers only see native failures as `DocxError`s.
* Keep a low-level escape hatch (e.g., export `addon` separately) if tooling needs the raw ABI, but documentation and typings should point everyone to the state-first `Etir` helper.

---

## 3) Data models (ETIR + SourceMap + Instructions)

### 3.1 ETIR (Editable Text IR)

**Scope**: *visible* text in WordprocessingML stories (main doc, table cells, headers/footers, footnotes, endnotes, comment bodies, text boxes). We deliberately ignore field **instructions**, numbering definitions, styles, drawing geometry, etc. The goal is a **clean text view** with **stable IDs** and **anchors** that an LLM can safely edit.

```json
{
  "version": "1.0",
  "fingerprint": {
    "fileHash": "sha256:…",
    "storyHashes": { "word/document.xml": "…", "word/footnotes.xml": "…" },
    "pidIndex": { "8B12": "word/document.xml#p[57]" }
  },
  "blocks": [
    {
      "part": "word/document.xml",
      "kind": "paragraph",            // paragraph | headerParagraph | footerParagraph | footnote | endnote | comment | textboxParagraph
      "pid": "8B12",                  // w14:paraId if present, else deterministic hash
      "style": "BodyText",            // optional
      "text": "The Company will issue…[^2]{cmt:12}",
      "anchors": [
        {"type":"footnoteRef","id":"2","at":63},
        {"type":"commentStart","id":"12","at":20},
        {"type":"commentEnd","id":"12","at":25}
      ],
      "protectedZones": [
        {"type":"fieldInstr","range":[31,48]},      // instrText between fldChar begin/separate
        {"type":"hyperlinkBoundary","at":12}        // start or end of w:hyperlink
      ]
    }
  ]
}
```

**Normalization (guarantees LLM sees predictable text):**

* Concatenate `w:t` runs respecting `xml:space`; map `w:tab`→`\t`, `w:br`→`\n`, `w:softHyphen`→U+00AD, `w:noBreakHyphen`→U+2011; `w:sym` → resolved glyph (or `{sym …}` token).
* Unicode NFC; **grapheme‑cluster** indexing (emoji/RTL safe).
* **Fields**: include **field results** only; mark **instructions** (`w:instrText` within `w:fldChar` begin/separate/end) as protected.
* Existing revisions: ETIR defaults to **flattened** (insertions included; deletions dropped) so you don’t get “diff of a diff” when you later compare. (You can allow a `revisions:"preserve"` mode if you need it.) *Motivation:* the revision family is complex (~28 elements).

**Anchors** we surface to the LLM but require to remain intact:

* `footnoteRef` / `endnoteRef` (body ↔ `/word/footnotes.xml`/`endnotes.xml` bodies).
* `commentStart`/`commentEnd` + a `commentReference` in the run flow (bodies in `/word/comments.xml`).
* `bookmarkStart`/`bookmarkEnd` (paired).
* `hyperlinkBoundary` (enter/exit of a `w:hyperlink` element).

**Text boxes**: paragraphs inside `w:drawing//wps:txbx/w:txbxContent` (Wordprocessing shapes) and legacy `w:pict/v:shape/v:textbox/w:txbxContent` appear as `kind:"textboxParagraph"` with stable handles; they are common in contracts and forms.

### 3.2 SourceMap (sidecar JSON)

Per‑block mapping from ETIR character ranges → **exact** OOXML locations:

```json
{
  "pid": "8B12",
  "segments": [
    {
      "irRange": [0, 12],
      "part": "word/document.xml",
      "paraOrdinal": 57,
      "runIndexPath": [12, 0],   // run 12, w:t 0
      "tCharRange": [0, 12]
    }
  ],
  "protectedZones": [
    {"type":"fieldInstr","range":[31,48]},
    {"type":"hyperlinkBoundary","at":12}
  ]
}
```

We use this only in `fromEtir` when rebuilding text safely.

### 3.3 InstructionsPack (LLM metadata)

Returned by `getInstructions`. Structure:

```json
{
  "schemaVersion": "1.0",
  "tokens": {
    "tab": "\\t",
    "lineBreak": "\\n",
    "softHyphen": "\u00AD",
    "noBreakHyphen": "\u2011",
    "anchors": {
      "footnoteRef": "Do not remove or move this reference.",
      "endnoteRef": "Do not remove or move.",
      "bookmarkStart": "Zero-width; must remain before bookmarkEnd(id).",
      "bookmarkEnd": "Zero-width; must remain after bookmarkStart(id).",
      "commentStart": "Zero-width; keep with matching commentEnd(id).",
      "commentEnd": "Zero-width; keep with commentStart(id).",
      "hyperlinkBoundary": "Do not cross this boundary."
    }
  },
  "allowedOperations": [
    "Rewrite text within each block’s `text` only.",
    "Preserve all anchors and their IDs/positions.",
    "Do not change field instructions; you may change visible field results."
  ],
  "examples": [
    { "before": "The Company agrees to issue...", "after": "The Company will issue..." }
  ],
  "systemPrompt": "You are editing structured text extracted from a Word document. Only modify words in `text`. Preserve anchors, tabs, line breaks. Do not alter field instructions."
}
```

---

## 4) Behavior of each endpoint

### 4.1 `toEtir(docx) → (etir.json, map.json)`

* Open the OPC/ZIP (`/word/*.xml` parts).
* Walk all **stories**: main `document.xml`, `header*.xml`, `footer*.xml`, `footnotes.xml`, `endnotes.xml`, `comments.xml`, plus paragraphs in text boxes (`wps:txbx` or legacy `v:textbox`).
* For each paragraph (`w:p`) enumerate runs/specials:

  * text `w:t`, tabs `w:tab`, breaks `w:br`, soft/no‑break hyphens, symbols `w:sym` → normalized text/tokens.
  * anchors: bookmarks, comment ranges, hyperlink boundaries, footnote/endnote refs.
  * **Fields**: mark instruction ranges (`w:instrText` within `w:fldChar` begin/separate/end) as protected, include result text.
* Emit ETIR blocks + SourceMap per paragraph.

### 4.2 `fromEtir(etir, base.docx) → after.docx`

* Sanity check **fingerprint** (avoid writing against a different base).
* For each changed block:

  * **Partition** paragraph into **segments** bounded by “islands” (field instruction regions, hyperlink boundaries, bookmark/comment bounds, optional math zones).
  * For each segment, replace visible text with the ETIR target text using **minimal runs**, inserting `w:tab` / `w:br` / `w:softHyphen` etc. as elements. Keep `w:pPr` (paragraph properties) and **do not** change container structure.
  * If an edit would delete/move anchors (strict mode) or cross a protected zone, return a **typed error** (no hidden “fallback” path).
* Validate (Open XML SDK validator semantics) and write `after.docx`.

> This gives you a clean after.docx you can give to any comparer (you’ll use `compare` next).

### 4.3 `compare(before.docx, after.docx) → review.docx`

* Call **WmlComparer** (`Compare(before, after, settings)`) to produce a third DOCX with **revision markup** (insertions/deletions, possibly other revision elements as needed). Set author/date.
* Current published builds explicitly call out **nested tables** and **text boxes** support (big wins for legal docs).
* Optional: expose `engine: "docx4j" | "word"` to switch to docx4j Differencer (JVM) or Word COM Compare (Windows) for parity testing or legal‑grade clients.

### 4.4 `getInstructions(etir) → instructions.json`

* Produce the **InstructionsPack** (above) so callers can paste **exact rules** into model prompts. This reduces anchor damage and cross‑boundary edits dramatically.

---

## 5) WordprocessingML content coverage (what exists; what we handle/guard/pass‑through)

> You **don’t** need to transform every tag. Because you generate the redline by *comparing two DOCX*, your only per‑tag logic is in `toEtir/fromEtir` for **visible text** and **anchors**. What follows is the coverage you must know about and cite.

### 5.1 Text & paragraph families (handled)

* **Paragraphs / runs / text**: `w:p`, `w:r`, `w:t` (Open XML SDK “Working with paragraphs/runs”). We also handle inline tokens `w:tab`, `w:br`, `w:softHyphen`, `w:noBreakHyphen`, `w:sym`.
* **Tables**: paragraphs inside table cells `w:tbl/w:tr/w:tc//w:p` are just paragraphs to us (compare supports nested tables).
* **Text boxes**: `w:drawing//wps:txbx/w:txbxContent//w:p` (2010+) and legacy `w:pict/v:shape/v:textbox/w:txbxContent//w:p`.
* **Headers/footers**: `/word/header*.xml`, `/word/footer*.xml` — same pattern; comparer handles them (note: Word’s UI may present those redlines differently, but they’re valid).

### 5.2 Anchors & ranges (guarded)

* **Hyperlinks**: `w:hyperlink` wraps runs; we treat **boundaries** as structural edges (edit inside OK; do not cross edges).
* **Bookmarks**: `w:bookmarkStart/End` — must remain paired; edits may not delete/reorder boundaries.
* **Comments**: `w:commentRangeStart/End` + `w:commentReference`; comment bodies live in `/word/comments.xml`.
* **Footnote/endnote references** in body (`w:footnoteReference` / `w:endnoteReference`) ↔ note bodies in `/word/footnotes.xml` / `/word/endnotes.xml`.

### 5.3 Fields (special handling)

* **Fields**: complex fields use `w:fldChar` (`begin`/`separate`/`end`) + `w:instrText` (instruction) and ordinary runs for **results**. ETIR includes **results only**; instructions are **protected**. Comparer diffs results just like normal text.

### 5.4 “Opaque” in v1 (pass‑through)

* **OMML math** (`m:oMath`, `m:oMathPara`) — leave intact (optionally surface a `{math}` token).
* **altChunk**, OLE, charts/SmartArt — pass through unchanged. (Your `compare` step will still produce valid redlines around text outside these objects.)

---

## 6) Implementation plan (Zig + C FFI + NativeAOT)

### 6.1 Compare engine (NativeAOT .NET → C ABI)

* Create a small .NET library with NuGet deps: **DocumentFormat.OpenXml** + **Open‑Xml PowerTools**.
* Export one function with `UnmanagedCallersOnly(EntryPoint="docx_compare")` that loads the two files, sets `WmlComparerSettings.AuthorForRevisions`, calls `WmlComparer.Compare`, and saves `review.docx`.
* Publish NativeAOT for: `linux-x64`, `linux-arm64`, `osx-arm64`, `win-x64`. You’ll get a true native `.so/.dylib/.dll` exposing the C entry point.

### 6.2 Zig library (the package you ship)

* **Link/Load** the NativeAOT lib (same folder) and declare:

  ```zig
  extern fn docx_compare([*:0]const u8, [*:0]const u8, [*:0]const u8, [*:0]const u8, ?[*:0]const u8) c_int;
  pub export fn etir_docx_compare(...) c_int { return docx_compare(...); }
  ```
* Implement `toEtir` and `fromEtir` in Zig using a streaming OPC reader + small XML cursor (or via a thin C helper if you prefer). You only need to read/write **text** and preserve boundaries as described above.
* `getInstructions`: read ETIR JSON and emit the `InstructionsPack`.

### 6.3 JavaScript bindings

* Build a **single N-API addon** straight from Zig (`src/lib_node.zig`). `zig build node` drops `etir.node` under `zig-out/lib/node/` and `zig build package` stages it into `bindings/js/dist/native/`.
* The bindings package resolves (in order) `process.env.ETIR_NATIVE_PATH`, the staged dist artifact, then the local `zig-out` build (mirroring our boilerplate). If none exists it throws with guidance to run `zig build package`.
* Expose a state-first `Etir` class as the primary JS interface (see Section 2 snippet). It:
  * requires a branded `Docx` buffer in the constructor, immediately captures ETIR + SourceMap + fingerprint, and never mutates the stored `document` baseline;
  * funnels every native call through shared helpers that map non-zero return codes to `DocxError`s while keeping `etir_docx_last_error()` private;
  * offers `getIr()`, `getSourceMap()`, `getDocument()`, `toReviewDocxFrom()`, `toReviewDocxTo()`, and `getInstructions()` so downstream code works entirely in memory.
* Optionally re-export the raw `addon` for tooling/tests, but documentation and typings should direct callers to the `Etir` helper by default.

### 6.4 Error codes (returned as non‑zero int; expose `etir_docx_last_error()`)

* `OPEN_FAILED_BEFORE` / `OPEN_FAILED_AFTER`
* `INVALID_DOCX_*` (Word would repair)
* `ETIR_STALE_BASE`, `ANCHOR_REMOVED`, `CROSSES_FIELD_INSTRUCTION`, `CROSSES_HYPERLINK_BOUNDARY`, `CROSSES_BOOKMARK_OR_COMMENT`, `UNSUPPORTED_ZONE`, `VALIDATION_FAILED`
* `COMPARE_FAILED`, `WRITE_FAILED_OUT`

---

## 7) Performance, security, ops

* **Run compare off the UI thread**; allow parallel compares with a worker pool.
* **Paths**: pass absolute paths; sanitize if you offer a CLI.
* **Logging**: filename + size + timings only (no content).
* **Memory**: stream large parts where possible; avoid materializing huge runs.
* **Determinism**: allow caller to pass author/date so diffs are reproducible in CI.

---

## 8) Verification plan (what you must pass to claim reliability)

**Corpus (ship it in a test repo)**

* Text with tabs, line breaks, soft/no‑break hyphens, emoji, RTL scripts.
* Tables with **nested tables**; merged cells. (Comparer updated to support this.)
* Headers/footers (with PAGE fields).
* Hyperlinks wrapping partial phrases.
* Dense bookmarks & comment ranges; heavy comment bodies.
* Footnotes/endnotes with cross‑refs.
* Text boxes (`wps:txbx` and legacy `v:textbox`).
* Fields (TOC/REF/PAGE): change **results**; leave instructions.

**Oracles**

1. All outputs open in Word **without a repair** prompt.
2. Reviewers confirm the redlines reflect the intended changes.
3. On Windows, cross‑check a subset against **Word’s Compare**; document any differences (notably legal numbering).

---

## 9) Why this design is the right abstraction

* **End‑to‑end**: ETIR makes AI editing safe; **compare** delivers **native**, trustworthy redlines.
* **Reliability**: we don’t invent revision markup; we reuse **WmlComparer**, an OSS module built expressly to output tracked changes for DOCX (now with nested tables & text boxes support).
* **Any content** claim is satisfied at the **compare** layer: since it compares two full DOCX packages, it is content‑agnostic (you aren’t hand‑mapping tags). For ETIR write‑back we **constrain to visible text**, which is precisely what the LLM should touch; everything else passes through untouched.

---

### References (primary & authoritative)

* **WmlComparer (Open‑Xml PowerTools)** — DOCX↔DOCX compare → tracked‑changes DOCX; recent release notes: **nested tables** & **text boxes** supported.
* **Eric White’s intro to WmlComparer** (what it does & why).
* **Open XML SDK docs** (WordprocessingML):

  * **Fields**: `FieldCode`/`instrText`; `FieldChar` (`w:fldChar` begin/separate/end).
  * **Hyperlink** (`w:hyperlink`).
  * **Comments** (`commentRangeStart/End`).
  * **FootnoteReference**.
  * **Text boxes**: `w:txbxContent`; modern shapes `wps:txbx`.
  * **Paragraphs & runs** (structure of visible text).
* **Spec mirrors / primers** (clear element semantics): **officeopenxml.com** on fields & hyperlinks; **c‑rex** on comments/footnotes.

---

## 10) What you hand to engineering (one‑pager)

* **Zig package** exporting 4 C ABI functions (`etir_docx_to_etir`, `etir_docx_from_etir`, `etir_docx_compare`, `etir_docx_get_instructions`) plus `etir_docx_last_error`.
* **NativeAOT .NET** engine exposing `docx_compare` used by Zig in `etir_docx_compare`.
* **JS bindings** via the Zig-built `etir.node` (Node-API) module, wrapped in the documented state-first `Etir` class that throws `DocxError`s on native failures.
* **Docs**: ETIR JSON schema, InstructionsPack JSON schema, error codes, constraints.
* **Tests**: corpus + oracles above; CI matrix runs compare on all platforms.

Ship **`compare`** first (it already works for any content); add `toEtir/fromEtir/getInstructions` right after for the AI editing flow. This gives you a small, robust, **Zig‑first** library that solves the entire “AI edits DOCX → trustworthy redline” pipeline without re‑implementing Word.
