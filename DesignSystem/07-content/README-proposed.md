![魏碑](DesignSystem/assets/github/readme-hero-1983x793.png)

# 魏碑

本地学习用的 macOS 工作台。

我做魏碑，是因为看课件时不想在浏览器、PDF、笔记软件和聊天窗口之间来回搬东西。材料在这里，笔记在那里，问到最后，最容易丢的反而是“这句话从哪来”和“我刚才在想什么”。

魏碑把阅读、笔记和课程对话放进同一个窗口。资料和笔记是主角，提问发生在它们旁边；回答尽量带回原文的位置，笔记是否写回仍由自己决定。

名字借的是书体，产品也按这个方向收：方一点，少一点装饰。界面有“纸面”和“墨石”两套，品牌字带一点魏碑的骨架，正文和笔记仍用系统字体。

![魏碑三栏工作台](DesignReferences/weibei-reference-01-overview.png)

## 现在能做什么

- 导入一个文件，或者直接导入整门课的目录；支持 HTML、PDF、Markdown 和纯文本
- 阅读网页、教材和笔记，记住上次看到的 PDF 页或 HTML 章节
- 给当前资料写 Markdown 笔记，把选中的原文直接摘进笔记
- 围绕当前资料、选区、笔记或整门课提问，并点回引用的文件、PDF 页或 HTML 章节
- 记住学习目标、已经掌握的内容、仍然困惑的问题和下一步；修改前会先让你确认
- 在三栏、文档与笔记对半、沉浸阅读、沉浸对话和沉浸写作之间切换

`⌘1`–`⌘4` 用来聚焦不同区域，`⌘B` 打开课程目录，`⌘K` 打开命令面板。

## 课程对话

魏碑用 PI 处理课程对话，但不会把整台电脑交给它。

应用先在本机索引当前课程，再找出和问题有关的材料、笔记、学习记录与对话，交给一轮干净的 PI 会话。PI 不能使用终端、网络，也不能随意读取文件系统。回答里的来源会由魏碑核对，能点回具体文件、PDF 页或 HTML 章节；整理笔记和更新学习记录时，它只能提出建议。

课程文件、笔记、索引和学习记录保存在本机，API Key 也只留在本机。模型服务仍可能需要联网，这取决于你使用的提供方。遇到还没索引完的长教材或扫描 PDF，魏碑会直接标明材料不完整，不把局部结果装成完整答案。

## 运行

目前请从源码运行。需要：

- macOS 14 或更高版本
- Xcode Command Line Tools
- 首次构建时可用的网络连接

```bash
git clone https://github.com/weibei-app/weibei.git
cd weibei
make run
```

第一次构建会下载并校验魏碑使用的固定版本 PI 运行体。开发环境要求 Node.js 22 与 npm；根目录 Makefile 只负责稳定入口和任务编排，具体实现由 Swift CLI 与 npm 承担。

课程对话需要可用的 PI 提供方认证。OpenAI Key 可以在设置中填写，也可以使用环境变量：

```bash
export OPENAI_API_KEY="..."
export WEIBEI_OPENAI_MODEL="gpt-5.1"
```

## 开发

```bash
make check
make package
make verify
```

几个有用的入口：

- [`DesignSystem/`](DesignSystem/)：品牌、产品规范与可发布资产
- [`DesignReferences/`](DesignReferences/)：界面与视觉参考
- [`Docs/MarkdownCompatibility.md`](Docs/MarkdownCompatibility.md)：Markdown 编辑兼容情况
- [`Sources/WeiBeiCore/AgentResources/`](Sources/WeiBeiCore/AgentResources/)：课程对话的技能、工具与边界
- [`Vendor/PiRuntime/`](Vendor/PiRuntime/)：内建 PI 运行体的版本、来源和维护说明

## 状态

魏碑还在开发中，界面、快捷键、课程索引和数据结构都可能继续调整。拿它记真实课程内容时，请自己备份重要笔记。

项目源代码采用 `AGPL-3.0-only`。`WeiBeiStele` 与 `WeiBeiSteleMono`
是项目自有品牌字体，不在 AGPL 授权范围内；复制、构建和再分发边界以
仓库根目录的 `LICENSING.md` 为准。
