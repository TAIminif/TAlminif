#!/usr/bin/env node
import { readFileSync, writeFileSync, statSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const compiled = resolve(root, '_build/js/release/build/cmd/main/main.js');
if (process.env.MOONC3D_NO_BUILD !== '1') {
  const build = spawnSync('moon', ['build', '--target', 'js', '--release'], { cwd: root, encoding: 'utf8', windowsHide: true });
  if (build.error || build.status !== 0) {
    process.stderr.write(build.error?.message || build.stderr || build.stdout || 'MoonBit build failed\n');
    process.exit(2);
  }
}
if (!existsSync(compiled)) {
  process.stderr.write('Build missing: run moon build --target js --release\n');
  process.exit(2);
}
const maximum = 128 * 1024 * 1024;
function readBytes(path) {
  const stat = statSync(path);
  if (!stat.isFile() || stat.size > maximum) throw new Error('Input must be a regular file of at most 128 MiB');
  const data = readFileSync(path);
  if (data.length > maximum) throw new Error('Input grew beyond 128 MiB');
  return new Uint8Array(data);
}
function writeNew(path, data) {
  if (Buffer.byteLength(data) > maximum) throw new Error('Output exceeds 128 MiB');
  writeFileSync(path, data, { flag: 'wx' });
}
globalThis.__moonC3D = {
  args: process.argv.slice(2), readBytes,
  readText: path => new TextDecoder('utf-8', { fatal: true }).decode(readBytes(path)),
  writeBytes: writeNew, writeText: writeNew,
  stdout: text => process.stdout.write(text),
  fail: (text, code) => { process.stderr.write(text + '\n'); process.exitCode = code; },
};
try { await import(pathToFileURL(compiled).href); }
catch (error) {
  process.stderr.write(JSON.stringify({ ok: false, error: 'HostIO', message: error.message }) + '\n');
  process.exitCode = 2;
}
