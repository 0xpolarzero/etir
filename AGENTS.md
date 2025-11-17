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
