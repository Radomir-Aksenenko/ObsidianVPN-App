// Stamps the version from the root VERSION file into every client manifest.
//
// Usage:
//   node scripts/set-version.mjs              # version only
//   node scripts/set-version.mjs 42           # version + iOS build number (CURRENT_PROJECT_VERSION)
//
// Touches: desktop/package.json, desktop/package-lock.json,
//          desktop/src-tauri/tauri.conf.json, desktop/src-tauri/Cargo.toml,
//          desktop/src-tauri/Cargo.lock, ios/project.yml

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const file = (rel) => join(root, rel);

const version = readFileSync(file('VERSION'), 'utf8').trim();
if (!/^\d+\.\d+\.\d+$/.test(version)) {
  throw new Error(`VERSION must look like X.Y.Z, got "${version}"`);
}

const buildArg = process.argv[2];
if (buildArg !== undefined && !/^\d+$/.test(buildArg)) {
  throw new Error(`Build number must be an integer, got "${buildArg}"`);
}

const changed = [];

function writeIfChanged(rel, before, after) {
  if (before === after) return;
  writeFileSync(file(rel), after);
  changed.push(rel);
}

function eolOf(text) {
  return text.includes('\r\n') ? '\r\n' : '\n';
}

// JSON manifests: parse, set fields, re-serialize with 2-space indent and original EOL.
function stampJson(rel, mutate) {
  const before = readFileSync(file(rel), 'utf8');
  const obj = JSON.parse(before);
  mutate(obj);
  const after = JSON.stringify(obj, null, 2).replace(/\n/g, eolOf(before)) + eolOf(before);
  writeIfChanged(rel, before, after);
}

// Top-level "version" key only (2-space indent), so formatting elsewhere stays untouched.
function stampTopLevelVersion(rel) {
  const before = readFileSync(file(rel), 'utf8');
  const re = /^(  "version":\s*")[^"]*(")/m;
  if (!re.test(before)) throw new Error(`top-level "version" not found in ${rel}`);
  writeIfChanged(rel, before, before.replace(re, `$1${version}$2`));
}

stampTopLevelVersion('desktop/package.json');
stampTopLevelVersion('desktop/src-tauri/tauri.conf.json');

// package-lock.json: top-level version plus the root package entry (packages[""]).
stampJson('desktop/package-lock.json', (lock) => {
  lock.version = version;
  if (lock.packages && lock.packages['']) {
    lock.packages[''].version = version;
  }
});

// Cargo.toml: the `version = "..."` line inside the [package] table only.
{
  const rel = 'desktop/src-tauri/Cargo.toml';
  const before = readFileSync(file(rel), 'utf8');
  const lines = before.split(/(\r?\n)/);
  let inPackage = false;
  let done = false;
  for (let i = 0; i < lines.length && !done; i += 2) {
    const line = lines[i];
    if (/^\s*\[/.test(line)) {
      inPackage = line.trim() === '[package]';
      continue;
    }
    if (inPackage && /^version\s*=\s*"[^"]*"/.test(line)) {
      lines[i] = line.replace(/^version\s*=\s*"[^"]*"/, `version = "${version}"`);
      done = true;
    }
  }
  if (!done) throw new Error(`No version field in [package] of ${rel}`);
  writeIfChanged(rel, before, lines.join(''));
}

// Cargo.lock: the entry for the desktop crate itself.
{
  const rel = 'desktop/src-tauri/Cargo.lock';
  const before = readFileSync(file(rel), 'utf8');
  const re = /(name = "obsidian-vpn"\r?\nversion = ")[^"]*(")/;
  if (!re.test(before)) throw new Error(`obsidian-vpn entry not found in ${rel}`);
  writeIfChanged(rel, before, before.replace(re, `$1${version}$2`));
}

// iOS: MARKETING_VERSION always, CURRENT_PROJECT_VERSION only when a build number is given.
{
  const rel = 'ios/project.yml';
  const before = readFileSync(file(rel), 'utf8');
  const marketing = /(MARKETING_VERSION:\s*")[^"]*(")/;
  const build = /(CURRENT_PROJECT_VERSION:\s*")[^"]*(")/;
  if (!marketing.test(before)) throw new Error(`MARKETING_VERSION not found in ${rel}`);
  let after = before.replace(marketing, `$1${version}$2`);
  if (buildArg !== undefined) {
    if (!build.test(after)) throw new Error(`CURRENT_PROJECT_VERSION not found in ${rel}`);
    after = after.replace(build, `$1${buildArg}$2`);
  }
  writeIfChanged(rel, before, after);
}

console.log(`Version ${version}${buildArg !== undefined ? `, build ${buildArg}` : ''}`);
for (const rel of changed) console.log(`  updated ${rel}`);
if (changed.length === 0) console.log('  nothing to change');
