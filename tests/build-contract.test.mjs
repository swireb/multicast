import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.env.MULTICAST_REPOSITORY_ROOT || process.cwd();
const ps = readFileSync(join(root, 'build.ps1'), 'utf8');
const sh = readFileSync(join(root, 'build.sh'), 'utf8');

for (const source of [ps, sh]) {
  assert.match(source, /0\.14\.1/);
  assert.match(source, /windows-amd64/);
  assert.match(source, /linux-amd64/);
  assert.match(source, /udp-sender/);
  assert.match(source, /udp-receiver/);
  assert.doesNotMatch(source, /packages\/multicast|packages\\multicast|assets\/multicast|assets\\multicast/);
}

assert.match(ps, /\[switch\]\$Check/);
assert.match(ps, /\[switch\]\$Clean/);
assert.match(ps, /\[switch\]\$DownloadToolchain/);
assert.match(sh, /--check/);
assert.match(sh, /--clean/);
assert.match(sh, /--download-toolchain/);
assert.match(ps, /if \(\$Clean\)[\s\S]*exit 0/);
assert.match(sh, /if \$clean; then clean_local; exit 0; fi/);
console.log('multicast build contract passed');
