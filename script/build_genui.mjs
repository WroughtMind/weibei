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
  // The shared loader adopts the promise; engines still load only on demand.
  const key = name === 'echarts-full' ? 'echartsFull' : name;
  const program = await readFile(outfile);
  await writeFile(outfile, `(window.__GenuiAssets__ ??= {}).${key} = ${packedProgram(program)}.then(() => window.__GenuiAssets__.${key});\n`);
}
// Authorize only the exact bundled programs; arbitrary inline scripts stay blocked.
const htmlPath = resolve(resources, 'genui.html');
const html = await readFile(htmlPath, 'utf8');
const policy = /script-src 'self'(?: 'sha256-[^']+')*;/;
assert(policy.test(html), 'GenUI script policy changed');
await writeFile(htmlPath, html.replace(policy, `script-src 'self' ${scriptHashes.join(' ')};`));

const skill = await readFile(require.resolve('@changfenhuang/dsh-genui/skill'), 'utf8');
const skillsFolder = resolve(root, 'Sources/WeiBeiCore/AgentResources/skills');
function listItem(prefix) {
  const marker = `- ${prefix}:`;
  const start = skill.indexOf(marker);
  assert(start >= 0, `上游 GenUI 技能缺少 ${prefix} 规格`);
  const tail = skill.slice(start);
  const boundaries = ['\n- ', '\n### ', '\n## ']
    .map(boundary => tail.indexOf(boundary, marker.length))
    .filter(index => index >= 0);
  return tail.slice(0, Math.min(...boundaries, tail.length)).trim();
}
function adaptHost(text) {
  return text
    .replaceAll('/mmx-files/', 'https://example.com/')
    .replaceAll('http(s) 或同源相对图片地址', 'HTTPS 图片地址')
    .replaceAll('仅 http(s) 或同源相对地址', '仅已确认的 HTTPS 地址')
    .replaceAll('无额外下载', '无需加载额外引擎')
    .replaceAll('但会按需下载约 1MB 引擎', '引擎随魏碑安装并按需加载')
    .replaceAll('`[genui-action]`', '互动操作请求')
    .replaceAll('围栏校验直接拒绝', '渲染器直接拒绝')
    .replaceAll('围栏会**静默降级为代码块**', '渲染器会报告错误，修正后重新调用 `render_ui`')
    .replace(/\*\*状态持久化[^\n]*/, '**状态保存**：选择、输入和提交状态由魏碑随当前会话中的界面保存。同一块界面保持稳定 id；不要把重提相同 id 当成重置。')
    .replace(/\*\*卷子模式[^\n]*/, '**用户明确要求自测时**，才用带唯一 group、answer、explanation 的 radio 和汇总 submit；普通解释不附题。');
}

const mainSkill = `# GenUI — 魏碑常用界面规范

本技能负责判断何时使用界面，以及常用组件的完整调用方法。Webi 的身份、语气、材料引用、记忆和笔记规则继续遵循系统契约；界面只帮助当前回答，不改变任务。

## 先判断：有结构才画，有操作才交互

口诀：纯解释直接说；并列信息用表；数量趋势用图；步骤用流程；确需用户输入再放控件。
两三句话能说清时不要调用 render_ui，也不要把普通回答包进卡片；不要把回答自动改成待办清单、练习或仪表盘，list 只用于真正并列的信息。

## 调用方式

调用 \`render_ui\`，参数必须含稳定的 \`id\` 和完整 \`spec\`；spec 至少有 items，可选 title、gap。
同一界面更新时复用 id，新界面换 id；id 只用小写字母、数字和连字符。
下方 JSON 是工具参数示例，不放进回答正文：

\`\`\`json
{"id":"concept-compare","spec":{"title":"观点与证据","items":[{"type":"table","columns":["项目","含义"],"rows":[["观点","对事情的判断"],["证据","支持判断的事实或资料"]]}]}}
\`\`\`

## 内容 → 组件

| 内容 | 组件 |
|---|---|
| 标题、段落、公式、代码 | text |
| 短内容横排或纵排 | row / col |
| 多组同级内容 | grid |
| 明细对照 | table |
| 关键数字、状态、进度 | stat / badge / progress |
| 并列项、键值、提醒 | list / keyvalue / callout |
| 阶段、操作顺序或时间轴 | steps / timeline |
| 简单数量、趋势、占比 | chart |
| 收集输入后继续处理 | input / select / textarea / submit |

## 高频组件规格

- text: \`{"type":"text","size":"h1|h2|h3|body|muted|caption","content":"富文本","center":true?}\`
- row: \`{"type":"row","items":[...],"wrap":true?,"spacer":true?}\`
- col: \`{"type":"col","items":[...],"gap":8?}\`
- grid: \`{"type":"grid","cols":2,"items":[...]}\`
- table: \`{"type":"table","columns":["列"],"rows":[["值"]]}\`；只要需要筛选 filter、导出 export、展开明细 details、列类型 types 或联动排序 sortField，无论行数，先加载 genui-advanced。
- stat: \`{"type":"stat","label":"指标","value":"42","delta":"+8%","spark":[3,5,4,8]}\`
- badge: \`{"type":"badge","label":"状态","tone":"success|warn|danger|accent"}\`
- progress: \`{"type":"progress","label":"进度","value":64,"valueLabel":"64%"}\`
- list: \`{"type":"list","items":["项目"]}\`
- keyvalue: \`{"type":"keyvalue","pairs":[{"key":"名称","value":"内容"}]}\`
- callout: \`{"type":"callout","tone":"info|success|warning|error","title":"提醒","content":"内容"}\`
- steps: \`{"type":"steps","current":1,"steps":[{"title":"步骤","desc":"说明"}]}\`
- timeline: \`{"type":"timeline","items":[{"title":"事件","desc":"说明","time":"第 1 天"}]}\`
- chart: \`{"type":"chart","kind":"bars|line|donut","data":[{"label":"A","value":1}]}\`；只做不超过 8 点的快速对比。
- button: \`{"type":"button","label":"继续","tone":"primary|danger|success|ghost","action":"continue"}\`
- input: \`{"type":"input","id":"query","label":"问题","placeholder":"请输入","inputType":"text|email|color"}\`
- select: \`{"type":"select","id":"choice","label":"选择","options":["甲","乙"],"selected":0?}\`
- textarea: \`{"type":"textarea","id":"note","label":"补充","rows":3,"value":""}\`
- submit: \`{"type":"submit","label":"继续","action":"continue"}\`；统一提交 fields，不给输入框重复设置 action。

## 富文本与公式

\`text.content\`、list、table 文本列、\`keyvalue.value\` 和 callout 支持行内代码、\`**粗体**\`、\`==高亮==\`、安全链接、行内公式 \`$x^2$\` 与独立公式 \`$$...$$\`；代码块使用 code 组件。只使用用户给出或确认可公开访问的 HTTPS 媒体地址。

## 版式三判据

1. 能否一眼看出主次：标题、正文、辅助说明各司其职。
2. 能否顺着阅读：长表、图表、步骤纵向铺开；row 只放短控件，grid 只并排同级内容。
3. 是否重复：同一信息只选最合适的表达；图看趋势，表查明细，正文不再逐项复述。

## 交互与边界

需要模型处理的 button 或 submit 才设置 action；本地排序、筛选、展开和选择无需逐次请求模型。
action 只是当前会话的互动请求，不代表检索、记忆或笔记操作已经完成；这些仍用原有工具。
用户明确要求自测时才使用题目和判分；不编造进度、掌握程度或材料数据。
不得索取或生成密码、API Key、访问令牌、恢复码等秘密输入。
只有收到已显示回执才能称已展示；渲染器报错时按原因修正后重调 render_ui。

表格只要需要筛选、导出、展开明细、列类型或联动排序，无论行数，或需要 13 种 ECharts 预设、full option、Diagram、Plot、3D 与低频组件时，先调用 \`load_skill\`，参数 \`{"id":"genui-advanced"}\`；加载后仍用 \`render_ui\`。`;

const advancedNames = [
  'table', 'echart', 'plot', 'diagram', 'scene3d',
  'hero', 'span', 'card', 'palette', 'divider', 'avatar', 'image', 'audio', 'video',
  'file-tree', 'breadcrumb', 'diff', 'json', 'code', 'mermaid', 'quiz',
  'checkbox', 'slider', 'radio', 'link', 'switch', 'tabs', 'accordion', 'copy',
];
const advancedSpecs = adaptHost(advancedNames.map(listItem).join('\n'));
const advancedTableExample = {
  id: 'course-table',
  spec: {
    title: '课程数据表',
    items: [
      { type: 'input', id: 'course-filter', label: '筛选课程', placeholder: '输入课程名称' },
      {
        type: 'table',
        columns: ['课程', '学分', '人数'],
        rows: [['高等数学', 4, 120], ['线性代数', 3, 90], ['概率论', 3, 80]],
        types: ['text', 'num', 'num'],
        export: true,
        filter: 'course-filter',
        filterColumn: 0,
        details: [
          [{ type: 'text', size: 'body', content: '微积分基础与函数分析课程。' }],
          [{ type: 'text', size: 'body', content: '向量、矩阵及线性方程组课程。' }],
          [{ type: 'text', size: 'body', content: '随机事件、概率模型与统计基础课程。' }],
        ],
      },
    ],
  },
};
const advancedSkill = `# GenUI Advanced — 魏碑高级界面规范

这是 GenUI 的按需补充。先遵循主技能的判断、富文本、版式与调用规则；只有任务确实需要下列能力时使用，不照着规格堆组件。

## 高级与低频组件

${advancedSpecs}

Diagram 默认省略 \`variant\`，让配色自动跟随宿主的深色或浅色主题；只有用户明确要求固定视觉主题时，才指定 \`light\`、\`dark\` 或 \`editorial\`。

## 容量与宿主边界

- 完整 spec 不超过 1 MB，组件树不超过 200 个节点、8 层嵌套。
- plot 必须给合理的 xMin/xMax；scene3d 只用于空间内容，mesh 控制在 1–5 个。
- diagram 建议不超过 9 个节点、12 条边；坐标型图按上方 kind 规则提供 x、y。
- 显示引擎随魏碑安装并按需加载；只使用用户给出或确认可公开访问的 HTTPS 媒体地址。

## 完整调用示例

这个例子演示本地筛选、内置导出和展开明细：filter 是输入框 id 字符串，export 是布尔值，details 与 rows 对齐且每项是组件数组或 null；不要使用 expandable，也不要另放导出按钮。

\`\`\`json
${JSON.stringify(advancedTableExample)}
\`\`\`

保持稳定 id，通过 \`render_ui\` 提交；若不再需要高级组件，继续按主技能选择最小表达。`;

const generatedNotice = '<!-- Generated from @changfenhuang/dsh-genui; edit script/build_genui.mjs for host integration. -->\n';
const mainOutput = `${generatedNotice}${mainSkill}\n`;
const advancedOutput = `${generatedNotice}${advancedSkill}\n`;
const mainLines = mainOutput.trimEnd().split('\n').length;
assert(mainLines >= 65 && mainLines <= 75, `主 GenUI 技能应为 65–75 行，当前 ${mainLines} 行`);
const echartPresets = ['bar', 'line', 'area', 'pie', 'scatter', 'radar', 'gauge', 'funnel', 'treemap', 'sankey', 'graph', 'heatmap', 'bigline'];
assert(echartPresets.every(preset => advancedOutput.includes(`\`${preset}\``)), '高级技能缺少 13 种 ECharts 预设');
assert(advancedOutput.includes('full option'), '高级技能缺少 ECharts full option');
assert(advancedOutput.includes('27 种') || advancedOutput.includes('27种'), '高级技能缺少 Diagram 27 种 kind');
assert(advancedOutput.includes('Diagram 默认省略 `variant`'), '高级技能缺少 Diagram 宿主主题规则');
for (const output of [mainOutput, advancedOutput]) {
  assert(!/dsh-ui|validate_dsh_ui|\/mmx-files\/|genui-usage-audit|design-reference|\[genui-action\]|硬触发/.test(output), 'GenUI 技能仍包含未适配的宿主说明');
}
const { processGenuiSpec } = await tsImport(resolve(dirname(require.resolve('@changfenhuang/dsh-genui/package.json')), 'src/client/guard.ts'), import.meta.url);
function validateSpec(name, spec) {
  const result = processGenuiSpec(spec);
  assert(result.spec && result.errors.length === 0 && result.warnings.length === 0, `${name}: ${JSON.stringify(result)}`);
  return result;
}
validateSpec('genui 高频规格', { items: [
  { type: 'text', size: 'h2', content: '**重点**与 $x^2$', center: true },
  { type: 'row', items: [{ type: 'badge', label: '就绪', tone: 'success' }], wrap: true, spacer: true },
  { type: 'col', items: [{ type: 'text', size: 'body', content: '纵排' }], gap: 8 },
  { type: 'grid', cols: 2, items: [{ type: 'stat', label: '数量', value: '42', delta: '+8%', spark: [3, 5, 4, 8] }, { type: 'progress', label: '进度', value: 64, valueLabel: '64%' }] },
  { type: 'table', columns: ['项目', '数值'], rows: [['甲', 1]] },
  { type: 'list', items: ['甲', { title: '乙', desc: '说明' }] },
  { type: 'keyvalue', pairs: [{ key: '名称', value: '内容' }] },
  { type: 'callout', tone: 'info', title: '提醒', content: '正文' },
  { type: 'steps', current: 1, steps: [{ title: '开始', desc: '说明' }] },
  { type: 'timeline', items: [{ title: '开始', desc: '说明', time: '第 1 天' }] },
  { type: 'chart', kind: 'bars', data: [{ label: '甲', value: 1 }] },
  { type: 'button', label: '继续', tone: 'primary', action: 'continue' },
  { type: 'input', id: 'query', label: '问题', placeholder: '请输入', inputType: 'text' },
  { type: 'select', id: 'choice', label: '选择', options: ['甲', '乙'], selected: 0 },
  { type: 'textarea', id: 'note', label: '补充', rows: 3, value: '' },
  { type: 'submit', label: '继续', action: 'continue' },
] });
validateSpec('genui-advanced 关键规格', { items: [
  { type: 'table', columns: ['项目', '变化'], rows: [['甲', '+8%']], types: ['text', 'delta'], total: true, export: true, filter: 'query', filterColumn: 0 },
  { type: 'echart', preset: 'sankey', data: [{ label: '访问', value: 120 }, { label: '注册', value: 45 }], links: [{ from: '访问', to: '注册', value: 45 }] },
  { type: 'plot', title: '函数', xMin: -3.14, xMax: 3.14, series: [{ expr: 'a*sin(x)', label: '曲线', params: [{ name: 'a', value: 1, min: 0, max: 2 }] }] },
  { type: 'diagram', kind: 'architecture', nodes: [{ id: 'a', label: 'Web', type: 'focal', x: 40, y: 40, w: 128, h: 48 }], edges: [] },
  { type: 'scene3d', title: '空间', meshes: [{ shape: 'box', size: 1, position: [0, 0, 0] }] },
  { type: 'hero', title: '摘要', subtitle: '说明', value: '42', label: '数量', delta: '+8%', spark: [3, 5, 4], tone: 'accent' },
  { type: 'grid', cols: 2, items: [{ type: 'card', title: '分组', span: 2, items: [{ type: 'divider' }, { type: 'spacer' }] }] },
  { type: 'chart', kind: 'donut', palette: ['#ff8800', '#3ecf8e'], data: [{ label: '甲', value: 1 }] },
  { type: 'avatar', name: 'Webi', color: '#336699' },
  { type: 'image', src: 'https://example.com/result.png', alt: '图片' },
  { type: 'audio', src: 'https://example.com/result.mp3', alt: '音频' },
  { type: 'video', src: 'https://example.com/result.mp4', alt: '视频', aspectRatio: '16:9' },
  { type: 'timeline', items: [{ title: '开始', desc: '说明', time: '今天' }] },
  { type: 'file-tree', items: [{ name: '资料', type: 'dir', children: [{ name: '说明.md', type: 'file' }] }] },
  { type: 'breadcrumb', items: ['首页', '资料'] },
  { type: 'diff', diffs: [{ path: '说明.md', oldText: '旧', newText: '新' }] },
  { type: 'json', value: { ready: true } },
  { type: 'code', lang: 'ts', code: 'const ready = true' },
  { type: 'mermaid', code: 'graph TD\\nA-->B' },
  { type: 'quiz', id: 'q1', question: '选哪项？', options: [{ label: '甲', correct: true }], explanation: '说明' },
  { type: 'checkbox', label: '甲', group: 'choices' },
  { type: 'slider', id: 'amount', label: '数量', min: 0, max: 10, step: 1, value: 5 },
  { type: 'radio', label: '选择', options: ['甲', '乙'], group: 'q1', answer: 0, explanation: '说明' },
  { type: 'link', label: '资料', href: 'https://example.com' },
  { type: 'switch', label: '启用', checked: true, action: 'toggle' },
  { type: 'tabs', tabs: [{ label: '甲', items: [{ type: 'text', size: 'body', content: '内容' }] }] },
  { type: 'accordion', items: [{ title: '详情', items: [{ type: 'text', size: 'body', content: '内容' }] }] },
  { type: 'copy', label: '复制', text: '内容' },
] });
const advancedTableResult = validateSpec('genui-advanced 表格示例', advancedTableExample.spec);
const repairedTable = advancedTableResult.spec.items.find(item => item.type === 'table');
assert.equal(repairedTable?.filter, 'course-filter', '高级表格示例的 filter 未保留');
assert.equal(repairedTable?.export, true, '高级表格示例的 export 未保留');
assert.deepEqual(repairedTable?.types, ['text', 'num', 'num'], '高级表格示例的 types 未保留');
assert(repairedTable?.details?.length === 3, '高级表格示例的 details 未完整保留');
assert(repairedTable.details.every(detail => detail?.[0]?.type === 'text'), '高级表格示例的 details 必须是组件数组');
for (const [name, output] of [['genui', mainOutput], ['genui-advanced', advancedOutput]]) {
  const examplesJSON = [...output.matchAll(/```json\n([\s\S]*?)\n```/g)];
  assert(examplesJSON.length >= 1, `${name} 缺少完整 JSON 示例`);
  for (const [, raw] of examplesJSON) {
    const { id, spec } = JSON.parse(raw);
    assert(/^[a-z0-9-]+$/.test(id), `${name} 示例必须有稳定 id`);
    validateSpec(`${name} 示例`, spec);
  }
}
for (const [id, output, manifest] of [
  ['genui', mainOutput, {
  id: 'genui', name: 'GenUI', version: genuiPackage.version,
  description: '常用生成式界面：负责使用判断、时间线、内容选型与基础交互；表格筛选、导出、展开明细、列类型或联动排序等高级能力需加载 genui-advanced。',
  modelInvocable: true, userInvocable: true, tools: ['render_ui'], jscHook: null,
  }],
  ['genui-advanced', advancedOutput, {
    id: 'genui-advanced', name: 'GenUI Advanced', version: genuiPackage.version,
    description: 'GenUI 按需高级补充：复杂长表、ECharts、Diagram、Plot、3D 与低频组件；先加载 genui。',
    modelInvocable: true, userInvocable: true, tools: ['render_ui'], jscHook: null,
  }],
]) {
  const folder = resolve(skillsFolder, id);
  await mkdir(folder, { recursive: true });
  await writeFile(resolve(folder, 'SKILL.md'), output);
  await writeFile(resolve(folder, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
}
console.log(`dshGenUI ${genuiPackage.version}: renderer, local engines, main and advanced skills bundled`);
