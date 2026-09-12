import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

test('asset check detects drift without rewriting the source manifest', () => {
  const root = mkdtempSync(join(tmpdir(), 'weibei-manifest-'));
  try {
    mkdirSync(join(root, 'assets'));
    writeFileSync(join(root, 'VERSION'), '1.0.0\n');
    writeFileSync(join(root, 'assets/probe.ttf'), 'font-proof');
    const args = ['--experimental-strip-types', fileURLToPath(new URL('./build-manifest.ts', import.meta.url)), root];
    execFileSync(process.execPath, args, { stdio: 'pipe' });
    execFileSync(process.execPath, [...args, '--check'], { stdio: 'pipe' });
    const manifest = join(root, 'assets/asset-manifest.json');
    writeFileSync(manifest, 'outdated manifest\n');
    const result = spawnSync(process.execPath, [...args, '--check'], { encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Asset manifest differs/);
    assert.equal(readFileSync(manifest, 'utf8'), 'outdated manifest\n');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
