import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative, resolve } from 'node:path';
import { build } from 'esbuild';

const root = resolve(import.meta.dirname, '..');
const source = resolve(root, 'Sources/WeiBei/WebEditor/src');
const resources = resolve(root, 'Sources/WeiBei/Resources/Editor');
const check = process.argv.includes('--check');
const output = check ? await mkdtemp(join(tmpdir(), 'weibei-editor-')) : resources;
const generated = new Set([
  'editor-entry.js', 'viewer-entry.js', 'katex-runtime.js', 'mermaid-runtime.js',
  'prism-runtime.js', 'editor.css', 'editor-resources.json', 'fonts', 'editor.js',
]);

const bundle = (entry, outfile, editable) => build({
  entryPoints: [resolve(source, entry)], bundle: true, format: 'iife', minify: true,
  outfile: resolve(output, outfile), define: { WEIBEI_EDITOR_RUNTIME: String(editable) },
  alias: editable ? {} : Object.fromEntries([
    '@milkdown/kit/plugin/clipboard', '@milkdown/kit/plugin/history', '@milkdown/kit/plugin/slash',
    '@milkdown/kit/plugin/upload', '@milkdown/kit/prose/history', '@milkdown/kit/prose/inputrules',
  ].map((name) => [name, resolve(source, 'viewerEditorStubs.ts')])),
  metafile: true, logLevel: 'warning',
});

if (!check) {
  for (const name of generated) await rm(resolve(resources, name), { recursive: true, force: true });
}
await mkdir(output, { recursive: true });

const [editorMeta, viewerMeta] = await Promise.all([
  bundle('editor-entry.ts', 'editor-entry.js', true),
  bundle('viewer-entry.ts', 'viewer-entry.js', false),
  bundle('vendor/katex-runtime.ts', 'katex-runtime.js', false),
  bundle('vendor/mermaid-runtime.ts', 'mermaid-runtime.js', false),
  bundle('vendor/prism-runtime.ts', 'prism-runtime.js', false),
  build({
    entryPoints: [resolve(root, 'node_modules/katex/dist/katex.css')], bundle: true, minify: true,
    outfile: resolve(output, 'editor.css'), loader: { '.woff': 'file', '.woff2': 'file', '.ttf': 'file' },
    // SPM .process 会把 bundle 内目录拍平;字体平铺输出 + css 同级相对路径才能在拍平后仍可解析。
    assetNames: '[name]', logLevel: 'warning',
  }),
]);

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
const manifest = `${JSON.stringify({ schemaVersion: 1, assets: entries }, null, 2)}\n`;
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
