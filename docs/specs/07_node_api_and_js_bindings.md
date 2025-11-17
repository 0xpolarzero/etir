# Spec 07 – Node‑API Addon and JS/TS Bindings

## 1. Scope

This spec covers the Node‑facing surface:

- A Node‑API addon built in Zig that wraps the C ABI exports and exposes them to JS.
- A TypeScript `Etir` helper class that provides an ergonomic API:
  - Loading DOCX from buffers/paths.
  - Generating ETIR + SourceMap.
  - Applying ETIR back to DOCX.
  - Running compare and getting instructions.

Primary files:

- `src/lib_node.zig`
- `bindings/js/package.json`
- `bindings/js/src/index.ts`
- Potentially, `bindings/js/src/*.spec.ts` (Vitest)

## 2. Repo & agent guidelines (local rules)

General:

- Align Node‑API filenames with Zig counterparts:
  - `src/lib_node.zig` ⇄ `bindings/js/src/index.ts`.
- Use Biome for formatting TS/JS:
  - 2‑space indentation, 100‑character lines, single quotes.
- Inline tests:
  - JS tests should live as `bindings/js/src/*.spec.ts`.

Concurrency / agent coordination:

- Treat C ABI (`src/lib_c.zig`) and ETIR internals as read‑only contracts:
  - Do not change function signatures in this spec.
  - If you need new behaviors, coordinate via Spec 01 and/or underlying Zig specs.
- Do not restore or replace existing JS/TS files; make targeted edits.
- Assume:
  - Native compare (Spec 06), ETIR extraction (Spec 03), and write‑back (Spec 04) may still be evolving; keep addon glue thin so internal changes don’t ripple.

## 3. Dependencies & parallelization

Dependencies:

- Spec 01: C ABI surface and error codes.
- Spec 02: Not directly; only via types returned to JS if needed.
- Specs 03–05: Determine behaviors of `to_etir`/`from_etir`/instructions, but addon can be wired with stub implementations early.

Parallelization:

- This spec can be developed largely in parallel with:
  - Spec 03 (ETIR extraction) and Spec 04 (write‑back).
  - Spec 06 (compare).
  - Spec 08 (build/tests/CI/security).
- The Node‑API addon can stub calls to C ABI until implementations are ready; once core functionality lands, plug it in without changing the JS API.

## 4. Implementation tasks (ordered)

1. Node‑API addon (`src/lib_node.zig`):
   - Implement a minimal Node‑API bootstrap:
     - Initialize N‑API environment.
     - Expose functions that mirror C ABI semantics but use JS‑friendly arguments (e.g., strings, `Uint8Array`s).
   - Map:
     - `etir_docx_to_etir` → JS method that accepts paths or buffers and returns parsed ETIR/SourceMap objects.
     - `etir_docx_from_etir` → method that accepts ETIR+SourceMap and returns a DOCX buffer.
     - `etir_docx_compare` → method returning a DOCX buffer with tracked changes.
     - `etir_docx_get_instructions` → method returning Instructions JSON.
   - Translate errors:
     - For non‑zero error codes, call `etir_docx_last_error` and throw a JS `Error` (or custom `DocxError`) with code + message.
2. JS/TS bindings (`bindings/js/src/index.ts`):
   - Implement the `Etir` class as sketched in the plan:
     - `constructor` takes environment options (paths, compare defaults, etc.).
     - Methods:
       - `toEtir(docx: Docx): { ir: EtirDocument; sourceMap: EtirSourceMap }`.
       - `fromEtir(base: Docx, ir: EtirDocument, sourceMap: EtirSourceMap, opts) → Docx`.
       - `compare(before: Docx, after: Docx, opts) → Docx`.
       - `getInstructions(ir: EtirDocument): Instructions`.
     - Use temp files or in‑memory paths to bridge Node ↔ C ABI where necessary.
3. Package metadata:
   - Configure `bindings/js/package.json` and build scripts to:
     - Build the addon (`zig build node` / `zig build package`).
     - Run tests (`npm run test` via Vitest).
4. Tests:
   - Add Vitest specs (`bindings/js/src/*.spec.ts`) covering:
     - Happy‑path ETIR extraction and write‑back.
     - Error propagation from C ABI (e.g., invalid DOCX, fingerprint mismatch).

## 5. Extract from full implementation plan

### 5.1 Node‑API binding (Zig)

From §12 of the full plan (truncated here; refer to full file for complete sketch):

> The Node layer loads the native Zig library (this same module) and marshals JS `Uint8Array` ↔ temp files only where needed (for compare). ETIR endpoints operate on disk paths per your C ABI, but the *JS helper* keeps UX all‑in‑memory.  
>  
> `src/lib_node.zig` (sketch; mini …)

### 5.2 Sample TypeScript helper (bindings/js/src/index.ts)

From §19 of the full plan:

```ts
export class Etir {
  // ... as in your spec ...
  #deriveEtir(): { ir: string; sourceMap: EtirSourceMap } {
    // Use tmp files for outputs; call addon.etir_docx_to_etir; read JSONs back into memory.
    // Clean up temp files.
    return { ir: jsonString, sourceMap: parsedMap };
  }

  #compare(before: Docx, after: Docx, opts: CompareOptions): Uint8Array {
    const author = opts.author ?? this.compareDefaults.author ?? 'etir';
    const dateISO = opts.dateISO ?? this.compareDefaults.dateISO ?? null;
    // Write before/after to temp files, call addon.etir_docx_compare, read review bytes.
    // Clean up and return Uint8Array.
  }

  #verifyFingerprint(candidate: Docx): void {
    // recompute fingerprint.fileHash from story parts only and compare to cached
    // throw DocxError('E10', 'ETIR fingerprint does not match base DOCX') on mismatch
  }
}
```

