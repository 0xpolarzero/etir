# etir

Composable Zig library with a native Node.js addon built in Zig. The root `build.zig` stays tiny and delegates to focused build files so native compilation, the `.node` addon, TypeScript bindings, testing, and linting remain independent yet orchestrated through a single entry point.

## Requirements
- Zig 0.15.2 (install via `asdf`, `mise`, Homebrew, etc.).
- Node.js 24.x LTS (ships with npm 10). Zig compiles the native addon against the Node 24 N-API headers, and we use npm scripts for the bindings workspace.
- Windows builds require the Node import library (`node.lib`). If it isn't next to your `node.exe`, the build will automatically download the matching `node.lib` from `nodejs.org` (cached under `.zig-cache/node-import-libs`). Set `NODE_ADDON_IMPORT_LIB` to override the path manually.
- The vendored ffi-napi patches currently target Node 20; newer majors may fail to build until we refresh `bindings/js/vendor/*`.

## Quickstart
```sh
npm install --prefix bindings/js
zig build                    # native static + shared libs
zig build node               # (optional) build the N-API addon only
zig build comparer           # publish the NativeAOT DOCX comparer for the current RID
zig build package           # builds addon, installs deps, emits dist/esm
zig build test               # Zig inline tests + Vitest (addon)
zig build lint               # zig fmt + Biome lint/format
zig build all                # lib + package + lint + test
zig build clean              # wipes Zig cache/out dirs + npm dist/node_modules
```
Use `npm --prefix bindings/js run <script>` if you want to invoke bindings scripts directly; otherwise let `zig build …` fan out to the right npm commands for you.

`zig build clean` removes `.zig-cache`, `zig-out`, and shells out to `npm run clean --prefix bindings/js`, so the bindings' `dist` and `node_modules` directories disappear as well.

## Layout & Build Entrypoints
```
.
├── build.zig                   # Main router delegating to the files below
├── build/
│   ├── common.zig              # Shared target / option plumbing
│   ├── lib.zig                 # Builds static/shared libs (core + C FFI)
│   ├── node.zig                # Builds the native .node addon via N-API
│   ├── js.zig                  # Typecheck + build Node bindings (runs npm scripts)
│   ├── package.zig             # Bundles addon+JS steps behind `zig build package`
│   ├── test.zig                # Zig unit tests + Vitest suite
│   ├── lint.zig                # Zig fmt + Biome lint/format
│   └── clean.zig               # Cleans Zig + Node artifacts
├── src/
│   ├── lib.zig                 # Pure Zig logic (with inline Zig tests)
│   ├── lib_c.zig               # C ABI surface (`pub export fn …`)
│   └── lib_node.zig            # N-API addon implementation
└── bindings/js/                # Node bindings (TypeScript, npm, Biome, Vitest)
```
Run each concern with Zig steps:
- `zig build` / `zig build lib` – builds the static/shared Zig libraries (`libetir.*`).
- `zig build node` – compiles the N-API addon (`etir.node`) that Node uses.
- `zig build package` – builds the addon, installs npm deps, stages `etir.node`, and runs the TypeScript build.
- `zig build test` – runs the inline Zig tests plus the Vitest suite (real addon, no mocks)—`zig build test --summary all` or `--verbose` for more details.
- `zig build lint` / `zig build fmt` – Biome lint/format for JS plus `zig fmt` for the Zig tree.
- `zig build all` – runs the library build, package, lint/format, and test steps in one go.
- `zig build clean` – Removes `.zig-cache`, `zig-out`, and runs the bindings clean script (which wipes `dist` and `node_modules`).

## Node Binding Workflow
1. Build the package: `zig build package` (includes the addon build, npm install, staging, and TypeScript emit).
2. Consume in Node: `import { etir } from '@etir/node';` which loads the staged `.node` addon and exposes the ergonomic JS API.
3. Tests/linting: `zig build test` and `zig build lint`, or run the npm scripts directly inside `bindings/js` if you need finer-grained control (`npm --prefix bindings/js run test`, etc.).

`bindings/js/scripts/stage-native.mjs` copies the freshly built `etir.node` into `bindings/js/dist/native`, writes a manifest, and is idempotent. The runtime loader (`bindings/js/src/index.ts`) resolves the addon via `ETIR_NATIVE_PATH`, staged assets, or `zig-out/lib/node` as a fallback, so local dev and packaged builds both “just work”.

## Notes
- The shared library exports `etir_add`, `etir_reduce`, `etir_checksum`, and `etir_version` with a C ABI for any environment that wants to link against C.
- Biome handles linting/formatting and Vitest runs against the real `.node` addon.
- Extend `src/lib.zig` for new functionality; the C ABI (`src/lib_c.zig`) and Node addon (`src/lib_node.zig`) stay thin wrappers over the same logic.
- The native addon is written entirely in Zig using N-API, so no third-party FFI dependencies are required at runtime.
