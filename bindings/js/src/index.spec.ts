import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { etir, __testing } from './index.js';

const SPEC_DIR = path.dirname(fileURLToPath(import.meta.url));
const DIST_NATIVE_DIR = path.resolve(SPEC_DIR, '../dist/native');
const STAGED_NATIVE = path.resolve(DIST_NATIVE_DIR, 'etir.node');

afterEach(() => {
  delete process.env.ETIR_NATIVE_PATH;
  vi.restoreAllMocks();
});

describe('etir addon', () => {
  it('adds numbers', () => {
    expect(etir.add(6, 7)).toBe(13);
  });

  it('checksums bytes deterministically', () => {
    expect(etir.checksum(Buffer.from('etir'))).toBe(0x2bb50a47);
  });

  it('reduces arrays with tolerance', () => {
    expect(etir.reduce([4, 4, 4], 8)).toBe(8);
  });

  it('reports version string', () => {
    expect(etir.version()).toContain('etir');
  });
});

describe('resolveNativeLibrary', () => {
  it('prefers ETIR_NATIVE_PATH when the override exists', () => {
    if (!fs.existsSync(STAGED_NATIVE)) {
      throw new Error('staged etir.node missing; run `zig build package` first.');
    }

    const overridePath = path.resolve(DIST_NATIVE_DIR, 'etir-env.node');
    fs.copyFileSync(STAGED_NATIVE, overridePath);
    process.env.ETIR_NATIVE_PATH = overridePath;
    try {
      expect(__testing.resolveNativeLibrary()).toBe(overridePath);
    } finally {
      fs.rmSync(overridePath, { force: true });
    }
  });

  it('falls back to the staged artifact', () => {
    if (!fs.existsSync(STAGED_NATIVE)) {
      throw new Error('staged etir.node missing; run `zig build package` first.');
    }
    delete process.env.ETIR_NATIVE_PATH;
    expect(__testing.resolveNativeLibrary()).toBe(STAGED_NATIVE);
  });

  it('throws when no candidate exists', () => {
    delete process.env.ETIR_NATIVE_PATH;
    const spy = vi.spyOn(fs, 'existsSync').mockReturnValue(false);
    expect(() => __testing.resolveNativeLibrary()).toThrow();
    spy.mockRestore();
  });
});
