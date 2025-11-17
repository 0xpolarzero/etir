#!/usr/bin/env node
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';

function parseArgs(argv) {
  const result = new Map();
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) continue;
    const [key, value] = arg.split('=', 2);
    if (value !== undefined) {
      result.set(key, value);
    } else {
      result.set(key, argv[i + 1]);
      i += 1;
    }
  }
  return result;
}

function ensure(value, message) {
  if (value == null) {
    throw new Error(message);
  }
  return value;
}

async function fileExists(targetPath) {
  try {
    await fsp.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    const request = https.get(url, (response) => {
      if (response.statusCode && response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        // Follow redirects.
        response.destroy();
        downloadFile(response.headers.location, dest).then(resolve).catch(reject);
        return;
      }
      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`Failed to download ${url} (status ${response.statusCode})`));
        return;
      }
      response.pipe(file);
      file.on('finish', () => file.close(resolve));
    });
    request.on('error', (err) => {
      fs.unlink(dest, () => reject(err));
    });
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const archTag = ensure(args.get('--arch'), 'Missing --arch');
  const cacheRoot = ensure(args.get('--cache'), 'Missing --cache');

  const version = process.versions.node;
  const versionTag = `v${version}`;
  const filename = `${versionTag}-${archTag}-node.lib`;
  const destDir = path.resolve(cacheRoot);
  const destPath = path.join(destDir, filename);
  await fsp.mkdir(destDir, { recursive: true });

  if (!(await fileExists(destPath))) {
    const url = `https://nodejs.org/download/release/${versionTag}/${archTag}/node.lib`;
    await downloadFile(url, destPath);
  }

  process.stdout.write(destPath);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
