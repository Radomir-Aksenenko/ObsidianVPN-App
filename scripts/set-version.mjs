// Stamps the version from the root VERSION file into app/pubspec.yaml.
//
// Usage:
//   node scripts/set-version.mjs
//
// Sets `version: <VERSION>+1` in app/pubspec.yaml. CI overrides the build number,
// so the +1 is only a placeholder. Nothing else is touched. No dependencies.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const version = readFileSync(join(root, 'VERSION'), 'utf8').trim();
if (!/^\d+\.\d+\.\d+$/.test(version)) {
  throw new Error(`VERSION must look like X.Y.Z, got "${version}"`);
}

const path = join(root, 'app', 'pubspec.yaml');
const before = readFileSync(path, 'utf8');
const matches = before.match(/^version:/gm) ?? [];
if (matches.length !== 1) {
  throw new Error(`expected one top-level "version:" line in app/pubspec.yaml, found ${matches.length}`);
}

// [^\r\n]* keeps the line ending (CRLF or LF) untouched.
const after = before.replace(/^version:[^\r\n]*/m, `version: ${version}+1`);

if (after === before) {
  console.log(`app/pubspec.yaml already at ${version}+1`);
} else {
  writeFileSync(path, after);
  console.log(`app/pubspec.yaml set to ${version}+1`);
}
