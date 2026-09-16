import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative, resolve } from 'node:path';
import { build } from 'esbuild';
import pako from 'pako';
import { packedWebScript } from './packed_web_script.mjs';
import { officeVendorPatches } from '../Sources/WeiBei/OfficeReader/vendor-patches.mjs';

const root = resolve(import.meta.dirname, '..');
const source = resolve(root, 'Sources/WeiBei/WebEditor/src');
const resources = resolve(root, 'Sources/WeiBei/Resources/Editor');
const check = process.argv.includes('--check');
const output = check ? await mkdtemp(join(tmpdir(), 'weibei-editor-')) : resources;
const generated = new Set([
  'editor-entry.js', 'viewer-entry.js', 'katex-runtime.js', 'mermaid-runtime.js',
  'prism-runtime.js', 'selection-runtime.js', 'office-entry.js', 'office-entry.js.deflate', 'whiteboard-runtime.js', 'reading-voice-runtime.js', 'voice-notices.txt', 'editor.css', 'editor-resources.json', 'fonts', 'editor.js',
]);

const bundle = (entry, outfile, editable, globalName) => build({
  entryPoints: [resolve(source, entry)], bundle: true, format: 'iife', minify: true,
  outfile: resolve(output, outfile), define: { WEIBEI_EDITOR_RUNTIME: String(editable) },
  alias: editable ? {} : Object.fromEntries([
    '@milkdown/kit/plugin/clipboard', '@milkdown/kit/plugin/history', '@milkdown/kit/plugin/slash',
    '@milkdown/kit/plugin/upload', '@milkdown/kit/prose/history', '@milkdown/kit/prose/inputrules',
  ].map((name) => [name, resolve(source, 'viewerEditorStubs.ts')])),
  metafile: true, logLevel: 'warning', globalName,
  ...(['vendor/mermaid-runtime.ts', 'whiteboard.ts'].includes(entry) ? { supported: { 'template-literal': false } } : {}),
});

if (!check) {
  for (const name of generated) await rm(resolve(resources, name), { recursive: true, force: true });
  for (const name of await readdir(resources)) {
    if (/^KaTeX_.*\.(?:ttf|woff)$/.test(name)) await rm(resolve(resources, name));
  }
}
await mkdir(output, { recursive: true });
if (check) {
  for (const name of ['Mplus1p-Light.woff2', 'Mplus1p-Regular.woff2', 'Mplus1p-Bold.woff2', 'diagram.html', 'office-licenses.txt', 'whiteboard.html', 'reading-voice.html', '课堂动作.webp', '情绪动作.webp', '独立口型.png', '素材清单.json', ...(await readdir(resources)).filter(name => name.startsWith('chinese-voice-'))]) {
    await writeFile(resolve(output, name), await readFile(resolve(resources, name)));
  }
}

const [editorMeta, viewerMeta] = await Promise.all([
  bundle('editor-entry.ts', 'editor-entry.js', true),
  bundle('viewer-entry.ts', 'viewer-entry.js', false),
  bundle('vendor/katex-runtime.ts', 'katex-runtime.js', false),
  bundle('vendor/mermaid-runtime.ts', 'mermaid-runtime.js', false),
  bundle('vendor/prism-runtime.ts', 'prism-runtime.js', false),
  bundle('selection.ts', 'selection-runtime.js', false, 'WeiBeiSelection'),
  bundle('whiteboard.ts', 'whiteboard-runtime.js', false),
  bundle('readingVoice.ts', 'reading-voice-runtime.js', false),
  build({ entryPoints: [resolve(root, 'Sources/WeiBei/OfficeReader/office.ts')], bundle: true, format: 'iife', minify: true, outfile: resolve(output, 'office-entry.js'), plugins: [officeVendorPatches], logLevel: 'warning' }),
  build({
    stdin: {
      contents: (await readFile(resolve(root, 'node_modules/katex/dist/katex.css'), 'utf8'))
        .replace(/,\s*url\([^)]*\.(?:woff|ttf)\)\s*format\("[^"]+"\)/g, ''),
      resolveDir: resolve(root, 'node_modules/katex/dist'), loader: 'css',
    },
    bundle: true, minify: true,
    outfile: resolve(output, 'editor.css'), loader: { '.woff2': 'file' },
    // 字体和编辑器样式同级，原生 App 与 SwiftPM 保持相同的 Editor 目录结构。
    assetNames: '[name]', logLevel: 'warning',
  }),
]);

await writeFile(resolve(output, 'voice-notices.txt'), (await Promise.all(['animalese-tts', 'pinyin-pro'].map(async name => name + '\n' + await readFile(resolve(root, 'node_modules', name, 'LICENSE'), 'utf8')))).join('\n\n'));
const officeBundle = resolve(output, 'office-entry.js');
// Use the existing pinned JSZip compressor for identical bytes across build hosts.
// Foundation inflates this bundled runtime once, before WebKit loads it.
await writeFile(`${officeBundle}.deflate`, pako.deflateRaw((await readFile(officeBundle, 'utf8')).replace(/[ \t]+$/gm, ''), { level: 9 }));
await rm(officeBundle);

// The editor and GenUI share one lazy relationship-diagram engine.
const mermaidBundle = resolve(output, 'mermaid-runtime.js');
const mermaid = packedWebScript(await readFile(mermaidBundle));
await writeFile(mermaidBundle, `window.WeiBeiMermaid = ${mermaid.source}.then(() => window.WeiBeiMermaid);
(window.__GenuiAssets__ ??= {}).mermaid = window.WeiBeiMermaid.then(() => window.__GenuiAssets__.mermaid);
`);
// The standalone board permits only this exact bundled Mermaid script to inflate inline.
const boardHTML = await readFile(resolve(resources, 'whiteboard.html'), 'utf8');
await writeFile(resolve(output, 'whiteboard.html'), boardHTML.replace(/script-src 'self'(?: 'sha256-[^']+')*;/, `script-src 'self' ${mermaid.hash};`));

const walk = async (directory) => (await Promise.all((await readdir(directory, { withFileTypes: true })).map(async (entry) => {
  const path = join(directory, entry.name);
  return entry.isDirectory() ? walk(path) : [path];
}))).flat();
const manifestFiles = (await walk(output)).filter((path) => !path.endsWith('/editor-resources.json'));
if (check) manifestFiles.push(resolve(resources, 'index.html'));
const entries = await Promise.all(manifestFiles.map(async (path) => {
  const bytes = await readFile(path);
  const name = path === resolve(resources, 'index.html') ? 'index.html' : relative(output, path);
  return { name, bytes: bytes.byteLength, sha256: createHash('sha256').update(bytes).digest('hex') };
}));
entries.sort((a, b) => a.name.localeCompare(b.name));
const manifest = `${JSON.stringify({ schemaVersion: 1, inlineScripts: [mermaid.hash], assets: entries }, null, 2)}\n`;
await writeFile(resolve(output, 'editor-resources.json'), manifest);

if (check) {
  const expected = new Map((await walk(output)).map((path) => [relative(output, path), path]));
  expected.set('index.html', resolve(resources, 'index.html'));
  const actual = new Map((await walk(resources)).map((path) => [relative(resources, path), path]));
  const differences = [];
  for (const name of new Set([...expected.keys(), ...actual.keys()])) {
    const left = expected.get(name); const right = actual.get(name);
    if (!left || !right || !(await readFile(left)).equals(await readFile(right))) differences.push(name);
  }
  const viewerInputs = Object.keys(viewerMeta.metafile.inputs);
  const viewerSource = await readFile(resolve(output, 'viewer-entry.js'), 'utf8');
  const indexSource = await readFile(resolve(resources, 'index.html'), 'utf8');
  if (viewerInputs.some((name) => /plugin-(?:history|slash|upload)|plugin\/(?:history|slash|upload)/.test(name))) {
    differences.push('viewer-editor-dependency');
  }
  if (['WEIBEI_BLOCK_COMMAND', 'dirtyChanged', 'requestSnapshot', 'snapshotReady', 'imagePickerRequested', 'weibei-math-source'].some((value) => viewerSource.includes(value))) {
    differences.push('viewer-editor-code');
  }
  if (!indexSource.includes("'./editor-entry.js'") || !indexSource.includes("'./viewer-entry.js'") || indexSource.includes('./editor.js')) {
    differences.push('index-entry-selection');
  }
  await rm(output, { recursive: true, force: true });
  if (differences.length) throw new Error(`Editor resources differ: ${differences.join(', ')}`);
}

const outputBytes = (meta, name) => Object.entries(meta.metafile.outputs).find(([path]) => path.endsWith(name))?.[1].bytes || 0;
console.log(`editor_entry_bytes=${outputBytes(editorMeta, 'editor-entry.js')}`);
console.log(`viewer_entry_bytes=${outputBytes(viewerMeta, 'viewer-entry.js')}`);
