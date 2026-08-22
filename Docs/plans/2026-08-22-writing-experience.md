# 笔记书写体验改善(对齐 Typora/Obsidian)· 执行计划

> 日期:2026-08-22 定稿(用户已拍板三项决策)
> 状态:分批执行中。批次① 随本 PR 交付;批次②③ 见文末路线图
> 取证基准:`origin/main @ aecfbe7`(含 #338 KaTeX 字体修复、#340 富回答退役)
> 产品原则:继承 `2026-08-19-wysiwyg-writing-engine.md`——纯 WYSIWYG、不做源码模式、解析失败不得丢内容、选区浮条归原生 SwiftUI

## 已定决策

1. 粘贴只拦"像 markdown"的,普通文字走原路;
2. 语法符号用单一淡雅色(Typora 风),不做每类一色;
3. 小补齐三项全做:⌘K 插链接、浮条删除线按钮、表格列宽拖拽。

## 现状取证(2026-08-22,均带行号)

- 编辑器是 Milkdown/ProseMirror 纯 WYSIWYG:`# `/`> `/`**x**`/`$x$`/`$$ ` 打字即时转换(inputrule 齐全,`editor.ts:109-113`、`mathExtension.ts:30-35`、commonmark/gfm preset 全开)。"样式改变"这半已成立。
- **粘贴断点的真实机理**(修正任务书的"replaceSelectionInternal 纯文本插入"之说):`replaceSelectionInternal` → `replaceRange` → `markdownToSlice` → `parserCtx`,是**完整 markdown 解析**(`node_modules/@milkdown/utils/lib/index.js:526-531`)。真正的问题是:聊天窗/网页复制时剪贴板同时携带 text/html,`handlePaste` 在 `normalized === text` 时放行(`editor.ts:2578`),Milkdown clipboard 插件随即**优先采用 HTML 解析结果**(`@milkdown/plugin-clipboard/lib/index.js:79`),markdown 源码落成字面文本。
- 打字半成品(`**重点` 未闭合)无待定色;光标进入已渲染粗体/标题/引用时源码符号不显示;公式仅点击/Enter 显源码——离 Typora/Obsidian 的显隐差距在这三处。

## 批次① 粘贴 markdown 即时渲染(本 PR)

**改动**:

1. `markdownRules.ts` 新增纯函数 `looksLikeMarkdownSyntax(text)`:保守探测标题/引用/列表/粗体/删除线/高亮/行内代码/配对公式/围栏/链接/图片/双链/callout/表格/分隔线/frontmatter;探测不到就放行默认粘贴路径。
2. `editor.ts` `handlePaste`:
   - 新增 `pasteTargetIsCode(view)` 守卫(仿 clipboard 插件的 code 守卫):光标在 code_block 或行内 code 内 → 放行字面粘贴;
   - 拦截条件从 `normalized === text` 收紧为 `normalized === text && !looksLikeMarkdownSyntax(normalized)`;
   - 命中即 `preventDefault` + `replaceSelectionInternal(normalized)`(单事务 = 一步撤销)。
3. 图片粘贴/拖拽分支、`normalizeMarkdownSource('userPaste')`(数学定界符归一 + 货币 `$100` 防护)、viewer stub 分支全部不动。

**测试**:`markdownRules.test.ts` 新增探测用例(正例 24、负例 10,含 `$100`/纯散文不触发);`WeiBeiWebEditorCheck` 新增 `validateRichClipboardPaste`:text/html+text/plain 同板粘贴 → 断言 2 个公式节点、1 个 strong、`\(x^2\)` 已转、`$100` 保留、撤销一步清空。

**边界与不做**:聊天窗若只复制出渲染后纯文本(无 markdown 源),编辑器侧无法恢复语法(记录为聊天侧复制出口问题,不在此修);富文本格式粘贴(无 markdown 语法)保持现状走 HTML。

## 批次②③ 路线图(后续 PR)

- **批次② `codex/syntax-marks`**:新文件 `WebEditor/src/syntaxMarks.ts`——打字半成品符号着色(未闭合 `**`/`$`/`#`/`>` 等,`weibei-syntax-pending`);光标进入 strong/emphasis/inlineCode/highlight/strike 时两端淡显符号、标题行首淡显 `#`、引用淡显 `>`(widget 装饰,`weibei-syntax-mark`);光标紧邻公式时淡显源码(`weibei-math-adjacent`,点击进入编辑不变)。严格选区局部计算,不做全树扫描;IME 组合与 agent 流式期间挂空。CSS 走四主题各加 `--weibei-syntax` 单色。
- **批次③ `codex/writing-extras`**:⌘K 复用原生链接弹窗;浮条加删除线(NotesAgentView +5 行内,PR 声明占用);接线 `columnResizingPlugin` 表格列宽拖拽。

## 验证链(每批相同)

`npm run typecheck:editor` → `npm run test:editor` → `npm run build:editor`(产物 diff 干净入库)→ `swift build` → `swift run WeiBeiSelfCheck` → `swift run WeiBeiWebEditorCheck` → `./script/build_and_run.sh run` 用户亲手试用 → `gh pr merge --merge --admin`。
