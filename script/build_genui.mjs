import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { basename, dirname, resolve } from 'node:path';
import { build } from 'esbuild';
import { tsImport } from 'tsx/esm/api';
import { packedWebScript } from './packed_web_script.mjs';

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
// Keep all syntax grammars offline; WebKit supplies gzip decoding on our OS targets.
const scriptPath = resolve(resources, 'genui.js');
const source = await readFile(scriptPath);
const scriptHashes = JSON.parse(await readFile(resolve(resources, 'Editor/editor-resources.json'), 'utf8')).inlineScripts;
function packedProgram(program) {
  const packed = packedWebScript(program);
  scriptHashes.push(packed.hash);
  return packed.source;
}
await writeFile(scriptPath, `${packedProgram(source)}.then(() => {
  if (!window.WeiBeiGenUIHost) throw new Error('GenUI initialization failed');
}).catch(error => {
  const status = document.getElementById('genui-status');
  status.textContent = '互动界面加载失败'; status.hidden = false;
  window.webkit?.messageHandlers?.weibeiGenUI?.postMessage({ type: 'error', message: String(error) });
});\n`);
for (const [name, entry] of Object.entries({ three: 'three', 'echarts-full': 'echarts' })) {
  const outfile = resolve(resources, `${name}.js`);
  await build({ ...options,
    entryPoints: [require.resolve(`@changfenhuang/dsh-genui/assets/${entry}`)],
    outfile,
  });
  if (name === 'echarts-full') {
    // The shared asset loader adopts this promise; charts still load only on demand.
    const program = await readFile(outfile);
    await writeFile(outfile, `(window.__GenuiAssets__ ??= {}).echartsFull = ${packedProgram(program)}.then(() => window.__GenuiAssets__.echartsFull);\n`);
  }
}
// Authorize only the exact bundled programs; arbitrary inline scripts stay blocked.
const htmlPath = resolve(resources, 'genui.html');
const html = await readFile(htmlPath, 'utf8');
const policy = /script-src 'self'(?: 'sha256-[^']+')*;/;
assert(policy.test(html), 'GenUI script policy changed');
await writeFile(htmlPath, html.replace(policy, `script-src 'self' ${scriptHashes.join(' ')};`));

const skill = await readFile(require.resolve('@changfenhuang/dsh-genui/skill'), 'utf8');
const folder = resolve(root, 'Sources/WeiBeiCore/AgentResources/skills/genui');
await mkdir(folder, { recursive: true });
const host = `# GenUI — 魏碑界面组件规范

本技能只说明界面组件的规格和呈现方式。Webi 的身份、交流方式、回答长短、材料检索、引用、学习记忆和笔记写入继续遵循系统契约与现有工具。界面文案跟随用户要求的语言，字段名、组件类型、id 和 action 保持原样。是否使用组件取决于它能否帮助回答当前问题，不按回答行数或组件数量强制使用。

围绕当前阅读、整理或讨论选择组件。只有用户明确要求练习、自测或探索参数变化时，才安排题目、判分或调参控件；不要把解释自动改成做题，不编造学习进度和掌握程度。

普通小表格直接用表头排序，不额外附加筛选框或排序下拉。需要用户查找大量记录时再提供筛选；组件已经展示清楚的内容，不在正文逐项复述。

## 调用方式

调用 \`render_ui\` 将组件插入当前回答，参数包含稳定的 \`id\` 和完整组件树 \`spec\`；spec 必须含 items，可选 title 和 gap。下文 JSON 示例都是工具参数，不作为回答正文输出。文字可以自然穿插在工具调用前后。

调用 \`render_ui\`，参数示例：

\`\`\`json
{"id":"concept-comparison","spec":{"title":"观点与证据","items":[{"type":"table","columns":["区别","观点","证据"],"rows":[["作用","说明作者的判断","支撑判断的事实或资料"],["例子","这本书适合入门","前两章使用了生活中的例子"]]}]}}
\`\`\`

- 同一条回答中用相同 id 更新原界面，用不同 id 插入另一块界面；id 只使用小写字母、数字和连字符。
- action 由魏碑转成当前会话中的互动请求。需要检索、记忆或笔记操作时，Webi 继续使用原有工具；按钮被点击不代表相关操作已经完成。
- 显示引擎随魏碑安装，按组件需要加载；只使用用户给出或已确认可公开访问的 HTTPS 图片、音视频地址。

`;
const start = skill.indexOf('富文本字段');
const end = skill.indexOf('\n## 范例', start);
assert(start >= 0 && end > start, '上游 GenUI 技能结构已变化，请核对魏碑接入说明');
// Keep upstream component documentation; replace only host delivery and workflow rules.
let body = skill.slice(start, end)
  .replace('组件词汇（只允许这些 type）', '组件词汇（先列常用类型，完整规格见后文）')
  .replace(/\*\*硬触发[^\n]*\n[\s\S]*?(?=\| 你要呈现的内容)/, '')
  .replace(/\*\*规则来自设计规范[\s\S]*?(?=### 三条判据)/, '')
  .replace(/### 怎么验证没模板化\n[\s\S]*$/, '')
  .replace(/\*\*状态持久化[^\n]*/, '**状态保存**：选择、输入和提交状态由魏碑随当前会话中的界面保存。同一块界面保持稳定 id；不要把重新提交相同 id 当成重置用户输入。')
  .replace('判卷、判题、重置、展开、选中', '排序、筛选、展开、选中、重置')
  .replace('"label":"交卷","action":"grade","groups":["q1","styles"],"resetAction":"redo"?', '"label":"继续讨论","action":"discuss","groups":["topics"]?,"resetAction":"redo"?')
  .replace(/\*\*卷子模式[^\n]*/, '**用户明确要求自测时**，可用 quiz；多道选择题使用带唯一 group、answer、explanation 的 radio，最后用 submit 汇总，本地显示结果。普通解释不附加题目。')
  .replace('同一批数据不做两种表达（表格与图表二选一）。', '避免无意义复述。图表看差异或趋势，表格查明细；用户明确要求两者时照做。')
  .replace(/### 卡片（`card`）只在两种场合用\n[\s\S]*?(?=### 层级靠字)/, '### 内容分组\n\n表格、图表、流程和输入控件直接放入布局，不再套 card；需要标题时使用 h3 文字节点。并排比较用 grid 直接放组件。card 仅用于多个内容确实属于同一对象的分组。不要逐段、逐项包卡，也不要嵌套卡片。\n\n')
  .replace(/### 层级靠字，不靠框\n[\s\S]*?(?=### 不要)/, '### 跟随魏碑主题与阅读宽度\n\n字号、颜色、边界和表面由魏碑主题统一处理，不指定固定底色、阴影或再套整块外框。用标题、段落和间距区分层级。图表、长表格和流程优先纵向铺开；并排使用 grid，row 只放短按钮、标签等内容，避免把图表挤进窄行。\n\n')
  .replace('超大数字（52px，带入场计数）', '突出数字（字号跟随魏碑主题，带入场计数）')
  .replace('| 教学 / 自测 / 判断题 |', '| 用户明确要求自测 / 判断题 |')
  .replaceAll('/mmx-files/', 'https://example.com/')
  .replace('http(s) 或同源相对图片地址', 'HTTPS 图片地址')
  .replace('仅 http(s) 或同源相对地址', '仅已确认的 HTTPS 地址')
  .replace('无额外下载', '无需加载额外引擎')
  .replace('但会按需下载约 1MB 引擎', '引擎随魏碑安装并按需加载')
  .replace('**交互组件必须带 action：不带 action 的按钮渲染为禁用态，用户点不了；带 action 的按钮点击后有「已触发」本地反馈。**', '**需要模型处理的操作才设置 action；按钮需要 action 才能触发。本地选择、筛选和展开无需逐次请求模型。**')
  .replace('`[genui-action]`', '互动操作请求')
  .replace('围栏校验直接拒绝', '渲染器直接拒绝')
  .replace('围栏会**静默降级为代码块**', '渲染器会报告错误，修正后重新调用 `render_ui`');
const examples = `
## 阅读与讨论示例：按内容选择，不照抄顺序

### 阅读材料：看数量差异，再安排整理步骤

用户给出教材 3 份、论文 20 篇、笔记 7 份，想看看材料构成并整理阅读顺序。图表占据完整阅读宽度，步骤放在下一段：

\`\`\`json
{"id":"reading-materials","spec":{"items":[{"type":"chart","kind":"bars","data":[{"label":"教材","value":3},{"label":"论文","value":20},{"label":"笔记","value":7}]},{"type":"steps","steps":[{"title":"梳理材料","desc":"标出各份材料讨论的问题"},{"title":"整理观点","desc":"把判断与支持它的证据分开"},{"title":"继续讨论","desc":"从尚未理解的地方开始"}]}]}}
\`\`\`

不要这样：用户只问数量，就额外安排阅读计划；用 row 把图表和长步骤挤在一起；材料没有给出时编造篇数。

### 继续讨论：输入后由用户明确提交

用户需要在界面中记下疑问再继续讨论。textarea 设置稳定 id，不带 action；submit 收集 fields 并发送一次请求。读取 fields.question 回答当前问题，按实际需要使用原有检索和笔记工具。

\`\`\`json
{"id":"reading-question","spec":{"items":[{"type":"textarea","id":"question","label":"记下疑问","placeholder":"哪一处还没想明白？","rows":3},{"type":"submit","label":"继续讨论","action":"discuss"}]}}
\`\`\`

不要这样：给输入框和提交按钮同时设置 action，导致离开输入框就发送；把普通疑问框命名为考试或交卷；每条回答都强塞一个讨论入口。

### 简短解释：直接回答

用户说“用两句话解释观点和证据”，直接回答：观点是你对一件事的判断。证据是用来支持这个判断的事实或资料。

不要这样：把两句话包进卡片，或反问用户来测试掌握程度。若用户之后要求比较多个具体例子，再用表格帮助看区别。
`;
const usage = `
## 使用规则

1. 只通过 \`render_ui\` 提交界面；普通文字、公式、代码和静态表格仍可直接写在回答里。组件内的文字、表格和代码用于组合界面，不必把普通回答再包一遍。
2. 参数必须是合法 JSON 对象，\`spec.items\` 使用上方组件规范。长表格或复杂内容可拆成几次调用，按内容安排顺序。
3. 魏碑渲染器校验组件。工具回执表示已提交，不代表界面已经正确显示；遇到错误时按具体原因修正后重新提交。
4. 布局按内容组合，主题跟随魏碑；不设置固定的组件数量，也不为满足版式而增加无关内容。
5. \`plot\` 给出合理的 xMin/xMax；3D 只用于几何或空间内容，mesh 少而精。
6. 完整 spec 不超过 1 MB，组件树不超过 200 个节点、8 层嵌套；同一份信息避免重复表达。
`;
const adaptedSkill = `${host}${body}${examples}${usage}`;
// Prevent retired DSH delivery paths from returning when the upstream skill changes.
assert(!/dsh-ui|validate_dsh_ui|\/mmx-files\/|genui-usage-audit|design-reference|\[genui-action\]|硬触发/.test(adaptedSkill), 'GenUI 技能仍包含未适配的宿主说明');
const { processGenuiSpec } = await tsImport(resolve(dirname(require.resolve('@changfenhuang/dsh-genui/package.json')), 'src/client/guard.ts'), import.meta.url);
const examplesJSON = [...adaptedSkill.matchAll(/```json\n([\s\S]*?)\n```/g)];
assert(examplesJSON.length >= 3, '魏碑 GenUI 示例缺失');
for (const [, raw] of examplesJSON) {
  const { id, spec } = JSON.parse(raw);
  assert(/^[a-z0-9-]+$/.test(id), '示例必须有稳定 id');
  const result = processGenuiSpec(spec);
  assert(result.spec && result.errors.length === 0 && result.warnings.length === 0, JSON.stringify(result));
}
await writeFile(resolve(folder, 'SKILL.md'), `<!-- Generated from @changfenhuang/dsh-genui; edit script/build_genui.mjs for host integration. -->\n${adaptedSkill}`);
await writeFile(resolve(folder, 'manifest.json'), `${JSON.stringify({
  id: 'genui', name: 'GenUI', version: genuiPackage.version,
  description: '使用 dshGenUI 在回答中呈现结构化组件、图表、表格与交互。',
  modelInvocable: true, userInvocable: true, tools: ['render_ui'], jscHook: null,
}, null, 2)}\n`);
console.log(`dshGenUI ${genuiPackage.version}: renderer, local engines and skill bundled`);
