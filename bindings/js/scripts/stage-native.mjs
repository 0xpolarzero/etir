#!/usr/bin/env node
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const bindingsDir = fileURLToPath(new URL('..', import.meta.url));
const defaultTargetDir = path.join(bindingsDir, 'dist/native');
const defaultBinary = 'etir.node';

function parseArg(args, name) {
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === `--${name}`) {
      return args[i + 1];
    }
    if (arg?.startsWith(`--${name}=`)) {
      return arg.slice(name.length + 3);
    }
  }
  return undefined;
}

const args = process.argv.slice(2);
const explicitSource = parseArg(args, 'source');
const explicitDest = parseArg(args, 'dest') ?? defaultTargetDir;

const sourcePath = await detectSource();
const filename = path.basename(sourcePath) || defaultBinary;
const destDir = explicitDest;
await fs.mkdir(destDir, { recursive: true });
const destPath = path.join(destDir, filename);
await fs.copyFile(sourcePath, destPath);

const manifest = {
  source: sourcePath,
  filename,
  arch: os.arch(),
  platform: os.platform(),
  kind: 'node-addon',
  stagedAt: new Date().toISOString(),
};
await fs.writeFile(path.join(destDir, 'manifest.json'), JSON.stringify(manifest, null, 2));

console.log(`[etir] staged native library -> ${destPath}`);

async function detectSource() {
  if (explicitSource) return explicitSource;
  if (process.env.ETIR_NATIVE_PATH) return process.env.ETIR_NATIVE_PATH;

  const primary = guessPath('lib');
  if (await exists(primary)) return primary;

  const secondary = guessPath('bin');
  if (secondary !== primary && (await exists(secondary))) return secondary;

  const hint = process.platform === 'win32' ? secondary : primary;
  throw new Error(
    `Missing native binary. Re-run via 'zig build ...' or pass --source (e.g. ${hint}).`,
  );
}

function guessPath(dir) {
  return path.resolve(bindingsDir, `../../zig-out/${dir}/node`, defaultBinary);
}

async function exists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}
