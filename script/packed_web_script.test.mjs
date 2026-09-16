import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import test from 'node:test';
import { packedWebScript } from './packed_web_script.mjs';

function compressedBytes(source) {
  const match = source.match(/atob\(("[^"]+")\)/);
  assert(match, 'packed script must contain gzip bytes');
  return Buffer.from(JSON.parse(match[1]), 'base64');
}

test('packed web script is deterministic and preserves the exact program bytes', () => {
  const program = Buffer.from('window.example = "魏碑";\n\0// packed runtime\n');
  const first = packedWebScript(program);
  const second = packedWebScript(program);

  assert.deepEqual(second, first);
  assert.deepEqual(gunzipSync(compressedBytes(first.source)), program);
  assert.equal(first.hash, `'sha256-${createHash('sha256').update(program).digest('base64')}'`);
  assert.match(first.source, /DecompressionStream\('gzip'\)/);
});
