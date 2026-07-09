# 魏碑

> 方笔入纸，有据可查。

魏碑是 macOS 上的**本地学习工作台**——不是又一个聊天壳，也不是云笔记的薄包装。

名字取自北朝碑刻书风：结体方峻、用笔有骨。产品也按这个脾气做：界面是纸与墨，对话要带出处，笔记写在材料边上，不把学习拆成「读一个 App、聊一个 App、记一个 App」。

```text
  资料库          阅读 / 碑面                笔记
 ────────    ─────────────────────    ──────────
  本地文件   HTML · PDF · Markdown     当场写回
             划线即问 · 有据回答         双链 · 公式
```

两套外观：**纸面**（暖纸、浓墨、朱砂点到为止）与 **墨石**（近黑底、碑面冷光）。品牌字体为作者自有，随仓库分发，不套系统默认「AI 产品脸」。

设计参考见 [`DesignReferences/`](DesignReferences/)——那是视觉系统，不是营销海报。

---

## 它坚持什么

**材料在场。** Agent 固定带着当前文档、选区、笔记与最近对话；没有 key 时给离线整理稿，不装成无所不知。

**出处优先。** 回答里能回指来源段落；划线浮层带真实摘录，可以写进笔记或替换选区——聊天记录不是终点，笔记才是。

**沉浸减负。** 阅读、对话、写笔记各有沉浸布局：只留当前任务该在的东西。对话里用户句是列内一角纸笺，助手句是正文，不堆聊天气泡墙。

**键盘先于鼠标。** `⌘1`–`⌘4` 切栏，`⌘B` 资料库，`⌘K` 命令面板；命令面板能插公式、Callout、Mermaid，不靠功能海。

**本地为家。** 笔记在本机 Application Support；Key 在本机配置。仓库不收你的课与密钥。

---

## 现在能做什么

| | |
| --- | --- |
| **读** | HTML（WebKit）、PDF（PDFKit，连续 / 单页，`⌘[` `⌘]`）、Markdown 渲染阅读 |
| **写** | Milkdown / ProseMirror 原地排版；源码与对照可切换；绑定当前资料 |
| **问** | 栏内对话、划线浮层、抽屉 / 小窗 / 静默洞察；上下文不漂移 |
| **排** | 文·话·笔三栏可调序；文档笔记对半；沉浸阅读 / 对话 / 写作 |
| **貌** | 纸面 · 墨石；朱砂作强调与选区，不用通用蓝紫渐变 |

尚在磨的：静默洞察要从「本地提示」长成真正的页级判断。那之前，宁可安静，不装聪明。

---

## 谁会对上脾气

- 对着课件、论文 PDF、导出的 HTML 记笔记，而不是从零开空白页  
- 划一句就要解释，并希望解释**写回**笔记，而不是沉在聊天记录里  
- 受不了默认「大模型产品」配色与圆角糖果，更想要一张能久坐的书桌  

若你要的是多智能体编排平台或云端第二大脑——魏碑不是那条路。

---

## 跑起来

**环境：** macOS 14+，`swift`（Xcode CLT）。改 Web 编辑器源码时需要 Node。

```bash
git clone https://github.com/taekchef/weibei.git
cd weibei
./script/build_and_run.sh
```

```bash
./script/build_and_run.sh check      # 自检
./script/build_and_run.sh package    # 只打 dist/魏碑.app
./script/build_and_run.sh --verify   # 自检 + 场景
```

### Agent

自备 Key，魏碑不代管账号。

| 变量 | 含义 | 默认 |
| --- | --- | --- |
| `OPENAI_API_KEY` | 模型调用 | 无 → 离线预览，不编造 |
| `WEIBEI_OPENAI_MODEL` | 模型名 | `gpt-5.1` |

也可在应用设置里填写；不入库、不进 git。

---

## 仓库怎么长

```text
Sources/WeiBei/        界面、沉浸布局、编辑器壳
Sources/WeiBeiCore/    工作区、Agent、密钥、PDF OCR
Sources/WeiBeiSelfCheck/
Sources/WeiBei/WebEditor/     笔记编辑器源码
Sources/WeiBei/Resources/     字体、打包后的 editor
DesignReferences/             纸 · 墨 · 石 · 朱砂 视觉稿
script/build_and_run.sh
```

主栈是 Swift 5.9 + SwiftUI/AppKit + PDFKit + WebKit。改对话栏、布局契约时，请顺手过 `WeiBeiSelfCheck`——这里用源码断言护着脾气，免得一改就滑成普通 Chat UI。

```bash
swift build
swift run WeiBeiSelfCheck
swift run WeiBeiWebEditorCheck
```

---

## 字与色

| 系统 | 角色 |
| --- | --- |
| **纸** | 纸张主色 / 次色——长时间阅读的底 |
| **墨** | 正文、次级、淡注 |
| **石** | 青灰结构、分割与静物 |
| **朱砂** | 强调、选区、少量动作——克制使用 |
| **字体** | 作者自研魏碑风格字体，正文与标题分级 |

不是「换了个中文字体的 Notion」，也不是套了宣纸贴图的 ChatGPT。碑在于骨：方、稳、有来处。

---

## 状态与许可

仍在打磨。布局、Agent 形态、沉浸细节都可能继续收。提 issue 前请先跑 `./script/build_and_run.sh check`。

开源许可待定。在 `LICENSE` 落地前，请勿默认可以任意再分发。字体为作者所有，随项目使用；若单独抽离字体，请先问。
