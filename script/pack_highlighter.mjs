// Lossless packaging for JavaScriptCore, which has no browser DecompressionStream.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import vm from 'node:vm';
import { build } from 'esbuild';
import { gzipSync } from 'three/addons/libs/fflate.module.js';

const path = process.argv[2];
assert(path, 'Usage: node script/pack_highlighter.mjs staged-highlight.min.js');
const original = await readFile(path, 'utf8');
const encoded = Buffer.from(gzipSync(Buffer.from(original), { level: 9, mtime: 0 })).toString('base64');
const result = await build({ stdin: { contents: `
  import { gunzipSync, strFromU8 } from 'three/addons/libs/fflate.module.js';
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const input = ${JSON.stringify(encoded)}, bytes = new Uint8Array(input.length * 3 / 4);
  let bits = 0, count = 0, offset = 0;
  for (const char of input) {
    if (char === '=') break;
    bits = bits * 64 + alphabet.indexOf(char); count += 6;
    if (count >= 8) { count -= 8; bytes[offset++] = bits >>> count & 255; bits &= (1 << count) - 1; }
  }
  (0, eval)(strFromU8(gunzipSync(bytes.subarray(0, offset))));
`, resolveDir: process.cwd() }, bundle: true, write: false, minify: true, format: 'iife', target: 'es2020' });
const packed = result.outputFiles[0].text;
const before = {}, after = {};
vm.runInNewContext(original, before); vm.runInNewContext(packed, after);
assert.equal(JSON.stringify(after.hljs.listLanguages()), JSON.stringify(before.hljs.listLanguages()));
for (const language of before.hljs.listLanguages()) {
  const text = 'const 答案 = "中文"; // example\nreturn 42 + value;';
  assert.equal(after.hljs.highlight(language, text, true).value, before.hljs.highlight(language, text, true).value, language);
}
await writeFile(path, packed);
console.log(`highlight_runtime_bytes=${Buffer.byteLength(packed)}; languages=${before.hljs.listLanguages().length}`);
