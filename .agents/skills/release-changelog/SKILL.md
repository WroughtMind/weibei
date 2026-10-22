---
name: release-changelog
description: >-
  Standardized workflow and template for drafting release notes, changelogs, and update summaries.
  Activate when preparing release notes, updating changelogs, writing appcast update summaries,
  or drafting GitHub Release descriptions for any version.
---

# 发版日志与更新说明（Release Changelog）工作流与规范

本技能规范魏碑项目的发版说明（Release Notes）、Changelog 以及应用内更新摘要（Sparkle Update Summaries）的证据收集、归类与撰写流程。

## 1. 核心原则

1. **结构极简干练**：正文只保留三大板块：**功能**（Features）、**改进**（Improvements）、**修复**（Bug Fixes）。**不加任何“须知”板块**（安装要求、架构、签名等环境信息在下载区与限制说明中体现，不混入变更列表）。
2. **拒绝假大空套话与长句**：每个条目控制在一到两句内，采用「**加粗核心名词**：直接陈述变化」结构，不讲废话，拒绝“XX更顺畅”、“XX更稳妥”等公关形容词。
3. **面向用户，拒绝内部代码黑话**：不提 actor、task cancellation、semaphore 等内部机制；从用户实际操作与体验结果切入。
4. **强制 PR 关联**：正文每个条目末尾必须标注关联的 PR 编号及链接（如 `([#539](https://github.com/WroughtMind/weibei/pull/539))`，在更新摘要中用 `(#539)`）。

## 2. 准备流程：收集 PR 与 Git 变动

撰写前必须通过实际 Git 提交与 PR 列表取证，不得凭空臆测，更不得漏掉关键体验修复：

1. **核对变动区间**：
   ```bash
   prev_tag="$(gh release list --limit 1 --exclude-drafts --json tagName --jq '.[0].tagName')"
   git log --oneline "$prev_tag"..HEAD
   ```

2. **完整映射 PR 列表**：
   ```bash
   gh pr list --state merged --limit 30
   ```
   对照每个 commit，逐项梳理出用户可感知的改动点，特别关注涉及崩溃、卡顿、保存防丢与交互响应的关键修复。

## 3. 双份产物格式标准

### 产物 A：GitHub Release 与官方文档（`Docs/releases/v<version>.md`）

```markdown
# 魏碑 <version>

## 功能
- **<功能名称>**：<简明描述，一句话直奔主题>。([#PR编号](https://github.com/WroughtMind/weibei/pull/PR编号))

## 改进
- **<改进名称>**：<相比上一版的体验提升或行为优化>。([#PR编号](https://github.com/WroughtMind/weibei/pull/PR编号))

## 修复
- **<修复缺陷>**：<消除的异常、崩溃、卡顿或错位行为>。([#PR编号](https://github.com/WroughtMind/weibei/pull/PR编号))

## 下载与安装
| 你的 Mac | 安装包 |
|---|---|
| Apple 芯片，包括 M 系列 | `WeiBei-<version>-macOS-arm64.dmg` |
| Intel 处理器 | `WeiBei-<version>-macOS-x86_64.dmg` |

...（校验文件、公证指引、Homebrew 安装命令）

## 使用与限制说明
...

## 反馈问题
...
```

### 产物 B：应用内更新摘要（`Docs/update-summaries/v<version>.md`）

供 Sparkle 弹窗使用，极度干练，不带多余段落：

```markdown
### 功能
- <功能简述> (#PR编号)

### 改进
- <改进简述> (#PR编号)

### 修复
- <修复简述> (#PR编号)
```

## 4. 发布与校验命令

1. **同步更新本地文档**：
   - `Docs/releases/v<version>.md`
   - `Docs/update-summaries/v<version>.md`
2. **更新线上 GitHub Release 说明**：
   ```bash
   gh release edit "v<version>" --notes-file "Docs/releases/v<version>.md"
   ```
3. **核查结果**：
   ```bash
   gh release view "v<version>"
   ```
