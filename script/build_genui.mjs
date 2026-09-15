import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { build } from 'esbuild';

const root = resolve(import.meta.dirname, '..');
const require = createRequire(resolve(root, 'package.json'));
const resources = resolve(root, 'Sources/WeiBei/Resources');
const genuiPackage = JSON.parse(await readFile(require.resolve('@changfenhuang/dsh-genui/package.json'), 'utf8'));
const options = {
  bundle: true, format: 'iife', minify: true, target: 'safari17', logLevel: 'warning',
  define: { 'process.env.NODE_ENV': '"production"' },
  supported: { 'template-literal': false },
  alias: { react: resolve(root, 'node_modules/react'), 'react-dom': resolve(root, 'node_modules/react-dom') },
  loader: { '.woff2': 'dataurl' },
  plugins: [{ name: 'local-math-fonts', setup(builder) {
    builder.onLoad({ filter: /katex.*\.css$/ }, async ({ path }) => ({
      contents: (await readFile(path, 'utf8')).replace(/,\s*url\([^)]*\.(?:woff|ttf)\)\s*format\("[^"]+"\)/g, ''),
      loader: 'css', resolveDir: dirname(path),
    }));
  } }],
};
await build({ ...options,
  entryPoints: [resolve(root, 'Sources/WeiBei/WebGenUI/host.tsx')],
  outfile: resolve(resources, 'genui.js'),
  jsx: 'automatic',
});
for (const [name, entry] of Object.entries({ mermaid: 'mermaid', three: 'three', 'echarts-core': 'echarts-core', 'echarts-full': 'echarts' })) {
  await build({ ...options,
    entryPoints: [require.resolve(`@changfenhuang/dsh-genui/assets/${entry}`)],
    outfile: resolve(resources, `${name}.js`),
  });
}

const skill = await readFile(require.resolve('@changfenhuang/dsh-genui/skill'), 'utf8');
const folder = resolve(root, 'Sources/WeiBeiCore/AgentResources/skills/genui');
await mkdir(folder, { recursive: true });
const host = `## 魏碑接入方式（优先于下文的 DSH 交付通道说明）

组件、字段、组合和交互全部遵循下方 dshGenUI 规范。魏碑用工具把组件穿插进当前回答：
- 调用 render_ui，参数为 {"id":"稳定的小写短标识","spec":{...}}；spec 使用下文完整组件树。
- 下文每个 dsh-ui 围栏示例对应一次 render_ui 调用，正文不输出 dsh-ui 围栏。同一 id 原位更新，不同 id 插入新界面。
- 不使用 DSH 的面板或插件命令。资源引擎已随魏碑安装；状态由当前会话保存，action 沿当前会话继续提问。
- 本宿主没有 validate_dsh_ui 工具；组件由同一份 dshGenUI 渲染器校验。工具受理只代表已提交，显示错误需按错误说明修正。
- 只引用用户给出或已确认可公开访问的图片、音视频地址，不使用 DSH 本地服务路径。

`;
const body = skill.replace(/^---\n[\s\S]*?\n---\n/, '');
await writeFile(resolve(folder, 'SKILL.md'), `<!-- Generated from @changfenhuang/dsh-genui; edit script/build_genui.mjs for host integration. -->\n${host}${body}`);
await writeFile(resolve(folder, 'manifest.json'), `${JSON.stringify({
  id: 'genui', name: 'GenUI', version: genuiPackage.version,
  description: '使用 dshGenUI 在回答中呈现结构化组件、图表、表格与交互。',
  modelInvocable: true, userInvocable: true, tools: ['render_ui'], jscHook: null,
}, null, 2)}\n`);
console.log(`dshGenUI ${genuiPackage.version}: renderer, local engines and skill bundled`);
