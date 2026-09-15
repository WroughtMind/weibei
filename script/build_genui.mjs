import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { basename, dirname, resolve } from 'node:path';
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
  plugins: [{ name: 'shared-host-resources', setup(builder) {
    builder.onResolve({ filter: /\.woff2$/ }, async ({ path, resolveDir }) => {
      const name = basename(path);
      const [font, shared] = await Promise.all([
        readFile(resolve(resolveDir, path)), readFile(resolve(resources, 'Editor', name)),
      ]);
      assert(font.equals(shared), `GenUI 数学字体与编辑器不一致：${name}`);
      return { path: `./Editor/${name}`, external: true };
    });
    builder.onLoad({ filter: /dsh-genui\/src\/client\/asset-loader\.ts$/ }, async ({ path }) => {
      const source = await readFile(path, 'utf8');
      const declaration = '  const file = `${name}.js`';
      assert(source.includes(declaration), '上游 GenUI 资源入口已变化，请核对共享资源映射');
      // Host packaging: one full chart engine; Mermaid also serves the editor.
      return { contents: source.replace(declaration, `  if (name === 'echarts-core') name = 'echarts-full'
  const file = name === 'mermaid' ? 'Editor/mermaid-runtime.js' : \`\${name}.js\``), loader: 'ts', resolveDir: dirname(path) };
    });
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
for (const [name, entry] of Object.entries({ three: 'three', 'echarts-full': 'echarts' })) {
  await build({ ...options,
    entryPoints: [require.resolve(`@changfenhuang/dsh-genui/assets/${entry}`)],
    outfile: resolve(resources, `${name}.js`),
  });
}

const skill = await readFile(require.resolve('@changfenhuang/dsh-genui/skill'), 'utf8');
const folder = resolve(root, 'Sources/WeiBeiCore/AgentResources/skills/genui');
await mkdir(folder, { recursive: true });
const host = `# GenUI — 魏碑界面组件规范

本技能只说明界面组件的规格和呈现方式。Webi 的身份、交流方式、回答长短、材料检索、引用、学习记忆和笔记写入继续遵循系统契约与现有工具。界面文案跟随用户要求的语言，字段名、组件类型、id 和 action 保持原样。是否使用组件取决于它能否帮助回答当前问题，不按回答行数或组件数量强制使用。

## 调用方式

调用 \`render_ui\` 将组件插入当前回答，参数包含稳定的 \`id\` 和完整组件树 \`spec\`；spec 必须含 items，可选 title 和 gap。下文 JSON 示例都是工具参数，不作为回答正文输出。文字可以自然穿插在工具调用前后。

调用 \`render_ui\`，参数示例：

\`\`\`json
{"id":"comparison","spec":{"title":"方案对比","gap":14,"items":[{"type":"table","columns":["方案","特点"],"rows":[["方案一","即时查看"],["方案二","可交互筛选"]]}]}}
\`\`\`

- 同一条回答中用相同 id 更新原界面，用不同 id 插入另一块界面；id 只使用小写字母、数字和连字符。
- action 由魏碑转成当前会话中的互动请求。需要检索、记忆或笔记操作时，Webi 继续使用原有工具；按钮被点击不代表相关操作已经完成。
- 显示引擎随魏碑安装，按组件需要加载；只使用用户给出或已确认可公开访问的 HTTPS 图片、音视频地址。

`;
const start = skill.indexOf('富文本字段');
const end = skill.indexOf('\n## 使用规则\n', start);
assert(start >= 0 && end > start, '上游 GenUI 技能结构已变化，请核对魏碑接入说明');
// Keep upstream component documentation; replace only host delivery and workflow rules.
let body = skill.slice(start, end)
  .replace('组件词汇（只允许这些 type）', '组件词汇（先列常用类型，完整规格见后文）')
  .replace(/\*\*硬触发[^\n]*\n[\s\S]*?(?=\| 你要呈现的内容)/, '')
  .replace(/\*\*规则来自设计规范[\s\S]*?(?=### 三条判据)/, '')
  .replace(/### 怎么验证没模板化\n[\s\S]*?(?=## 范例)/, '')
  .replace(/\*\*状态持久化[^\n]*/, '**状态保存**：选择、输入和交卷状态由魏碑随当前会话中的界面保存。同一块界面保持稳定 id；不要把重新提交相同 id 当成重置用户输入。')
  .replaceAll('/mmx-files/', 'https://example.com/')
  .replace('http(s) 或同源相对图片地址', 'HTTPS 图片地址')
  .replace('仅 http(s) 或同源相对地址', '仅已确认的 HTTPS 地址')
  .replace('无额外下载', '无需加载额外引擎')
  .replace('但会按需下载约 1MB 引擎', '引擎随魏碑安装并按需加载')
  .replace('**交互组件必须带 action：不带 action 的按钮渲染为禁用态，用户点不了；带 action 的按钮点击后有「已触发」本地反馈。**', '**需要模型处理的操作才设置 action；按钮需要 action 才能触发。本地选择、筛选和展开无需逐次请求模型。**')
  .replace('`[genui-action]`', '互动操作请求')
  .replace('围栏校验直接拒绝', '渲染器直接拒绝')
  .replace('围栏会**静默降级为代码块**', '渲染器会报告错误，修正后重新调用 `render_ui`');
let exampleCount = 0;
body = body.replace(/```json dsh-ui(-bad)?\n([\s\S]*?)\n```/g, (_, bad, raw) => {
  const argumentsJSON = JSON.stringify({ id: `example-${++exampleCount}`, spec: JSON.parse(raw) });
  return `${bad ? '错误参数示例（不要调用）' : '调用 `render_ui`，参数示例'}：\n\n\`\`\`json\n${argumentsJSON}\n\`\`\``;
});
const usage = `
## 使用规则

1. 只通过 \`render_ui\` 提交界面；普通文字、公式、代码和静态表格仍可直接写在回答里。组件内的文字、表格和代码用于组合界面，不必把普通回答再包一遍。
2. 参数必须是合法 JSON 对象，\`spec.items\` 使用上方组件规范。长表格或复杂内容可拆成几次调用，按内容安排顺序。
3. 魏碑渲染器校验组件。工具回执表示已提交，不代表界面已经正确显示；遇到错误时按具体原因修正后重新提交。
4. 布局按内容组合，主题跟随魏碑；不设置固定的组件数量，也不为满足版式而增加无关内容。
5. \`plot\` 给出合理的 xMin/xMax；3D 只用于几何或空间内容，mesh 少而精。
6. 完整 spec 不超过 1 MB，组件树不超过 200 个节点、8 层嵌套；同一份信息避免重复表达。
`;
const adaptedSkill = `${host}${body}${usage}`;
// Prevent retired DSH delivery paths from returning when the upstream skill changes.
assert(exampleCount > 0, '上游 GenUI 调用示例缺失');
assert(!/dsh-ui|validate_dsh_ui|\/mmx-files\/|genui-usage-audit|design-reference|\[genui-action\]|硬触发/.test(adaptedSkill), 'GenUI 技能仍包含未适配的宿主说明');
await writeFile(resolve(folder, 'SKILL.md'), `<!-- Generated from @changfenhuang/dsh-genui; edit script/build_genui.mjs for host integration. -->\n${adaptedSkill}`);
await writeFile(resolve(folder, 'manifest.json'), `${JSON.stringify({
  id: 'genui', name: 'GenUI', version: genuiPackage.version,
  description: '使用 dshGenUI 在回答中呈现结构化组件、图表、表格与交互。',
  modelInvocable: true, userInvocable: true, tools: ['render_ui'], jscHook: null,
}, null, 2)}\n`);
console.log(`dshGenUI ${genuiPackage.version}: renderer, local engines and skill bundled`);
