import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';

const pluginRoot = 'plugins/scorace-learning';
const readJson = (file) => JSON.parse(readFileSync(file, 'utf8'));
const release = readJson(`${pluginRoot}/learning-release.json`);
const plugin = readJson(`${pluginRoot}/.codex-plugin/plugin.json`);
const marketplace = readJson('.agents/plugins/marketplace.json');

assert.equal(plugin.name, 'scorace-learning');
assert.equal(release.schema, 'scorace-learning-release/v1');
assert.equal(plugin.version, release.plugin_version);
assert(marketplace.plugins.some((entry) =>
  entry.name === plugin.name &&
  entry.source?.source === 'local' &&
  entry.source.path === `./${pluginRoot}`));

function filesUnder(dir, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const relative = path.posix.join(prefix, entry.name);
    if (entry.isDirectory()) return filesUnder(path.join(dir, entry.name), relative);
    assert(entry.isFile(), `Unexpected file type: ${relative}`);
    return relative === 'learning-release.json' ? [] : [relative];
  });
}

const actual = filesUnder(pluginRoot).sort();
const expected = release.files.map((entry) => entry.path).sort();
assert.deepEqual(expected, actual, 'Release file inventory differs from Plugin files');

for (const entry of release.files) {
  const content = readFileSync(path.join(pluginRoot, entry.path));
  assert.equal(entry.bytes, content.length, `${entry.path}: byte size`);
  assert.equal(entry.sha256, createHash('sha256').update(content).digest('hex'), `${entry.path}: SHA-256`);
}

console.log(`Validated ${actual.length} public Plugin files for ${plugin.version}`);
