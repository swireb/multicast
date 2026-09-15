import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.env.MULTICAST_REPOSITORY_ROOT || process.cwd();
const file = (relative) => join(root, relative);
const read = (relative) => readFileSync(file(relative), 'utf8');

for (const relative of [
  'src/COPYING',
  'src/udp-sender.c',
  'src/udp-receiver.c',
  'patches/0001-windows-amd64-types.patch',
  'upstream.lock.json',
  'build.ps1',
  'build.sh',
  '.github/workflows/build.yml',
]) {
  assert.equal(existsSync(file(relative)), true, `missing ${relative}`);
}

const ignored = read('.gitignore');
assert.match(ignored, /^\/build\/$/m);
assert.match(ignored, /^\/output\/$/m);

const lock = JSON.parse(read('upstream.lock.json'));
assert.equal(lock.upstream, 'udpcast');
assert.equal(lock.version, '20250223');
assert.equal(lock.source.sha256, 'cefd7554c877e1bc76987d2b96b23f7699a2e5340c254454f61b6e0dae370aa7');
assert.equal(lock.toolchain.zig.version, '0.14.1');

const workflow = read('.github/workflows/build.yml');
assert.match(workflow, /push:/);
assert.match(workflow, /pull_request:/);
assert.match(workflow, /workflow_dispatch:/);
assert.match(workflow, /refs\/tags\/v/);
assert.match(workflow, /udpcast-windows-amd64/);
assert.match(workflow, /udpcast-linux-amd64/);
assert.match(workflow, /udp-sender/);
assert.match(workflow, /udp-receiver/);
assert.match(workflow, /actions\/checkout@[0-9a-f]{40}/);
assert.match(workflow, /actions\/upload-artifact@[0-9a-f]{40}/);
assert.match(workflow, /actions\/download-artifact@[0-9a-f]{40}/);
assert.doesNotMatch(workflow, /uses:\s+[^\n]+@v\d/u);
assert.match(workflow, /gh release create/);
assert.match(workflow, /Set-Content -Encoding ascii release\/SHA256SUMS/);
assert.doesNotMatch(workflow, /Set-Content -NoNewline release\/SHA256SUMS/);
assert.match(workflow, /\$\(\$_\.Hash\.ToLowerInvariant\(\)\)  \$\(\$_\.Path \| Split-Path -Leaf\)/);

console.log('multicast repository contract passed');
