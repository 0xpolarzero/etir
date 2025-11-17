import { describe, expect, it } from 'vitest';
import { etir } from './index.js';

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
