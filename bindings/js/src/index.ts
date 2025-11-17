import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));
const requireNative = createRequire(import.meta.url);

export interface EtirClient {
  add(a: number, b: number): number;
  checksum(input: Buffer | Uint8Array | string): number;
  reduce(values: readonly number[], tolerance?: number): number;
  version(): string;
}

export type NativeExports = {
  etir_add: (a: number, b: number) => number;
  etir_checksum: (buffer: Buffer) => number;
  etir_reduce: (buffer: Buffer, tolerance: number) => number;
  etir_version: () => string;
};

let cachedBinding: NativeExports | undefined;
let cachedPath: string | undefined;

function ensureBinding(): NativeExports {
  if (cachedBinding) return cachedBinding;
  const resolvedPath = cachedPath ?? resolveNativeLibrary();
  cachedPath = resolvedPath;
  cachedBinding = requireNative(resolvedPath) as NativeExports;
  return cachedBinding;
}

function resolveNativeLibrary(): string {
  const explicit = process.env.ETIR_NATIVE_PATH;
  if (explicit && fs.existsSync(explicit)) {
    return explicit;
  }

  const staged = path.resolve(MODULE_DIR, '../dist/native/etir.node');
  if (fs.existsSync(staged)) {
    return staged;
  }

  const local = path.resolve(MODULE_DIR, '../../zig-out/lib/node/etir.node');
  if (fs.existsSync(local)) {
    return local;
  }

  throw new Error(
    'Unable to locate etir.node; run `zig build package` first or set ETIR_NATIVE_PATH.',
  );
}

function encodeInt32Slice(values: readonly number[]): Buffer {
  const buffer = Buffer.alloc(values.length * 4);
  for (let i = 0; i < values.length; i += 1) {
    buffer.writeInt32LE(values[i] | 0, i * 4);
  }
  return buffer;
}

function encodeBytes(input: Buffer | Uint8Array | string): Buffer {
  if (Buffer.isBuffer(input)) return input;
  if (typeof input === 'string') return Buffer.from(input, 'utf8');
  return Buffer.from(input.buffer, input.byteOffset, input.byteLength);
}

export const etir: EtirClient = {
  add(a, b) {
    return ensureBinding().etir_add(a | 0, b | 0);
  },
  checksum(input) {
    const bytes = encodeBytes(input);
    return ensureBinding().etir_checksum(bytes) >>> 0;
  },
  reduce(values, tolerance = 8) {
    const slice = encodeInt32Slice(values);
    return ensureBinding().etir_reduce(slice, Math.max(0, tolerance) >>> 0);
  },
  version() {
    return ensureBinding().etir_version();
  },
};

export const __testing = {
  resolveNativeLibrary,
};
