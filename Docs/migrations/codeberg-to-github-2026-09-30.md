# Codeberg → GitHub 迁回记录（2026-09-30）

GitHub `WroughtMind/weibei` 恢复为主要开发仓库。Codeberg 保留来源历史和讨论，不删除或强推来源仓库。

## 主线与来源

- 迁移前 GitHub main：`97c97800d8ced9e3a16900ddb12193591b958ad5`
- 来源 Codeberg main：`c98803055954d239f93644899122fae579659db7`
- 主线迁移 PR：[GitHub #512](https://github.com/WroughtMind/weibei/pull/512)
- 共同历史，Codeberg 多 62 个提交，GitHub 独有 0 个；原作者、时间、父子关系与 SHA 保留
- 同名分支中 22 个完全相同；30 个 Codeberg 独有分支和领先的 DeepSeek 分支保存到 `codeberg/<原分支名>`，未覆盖 GitHub 原分支
- 原始 annotated tag 对象：`v0.1.0` → `2778ead37a8db9e4d2adaba580c8a7a133a500ba`；`v1.0.0` → `afeb3c37b1d88eb4b700e76c1e56720e0d96165c`

标签保存不代表重新发布对应安装包。

## 开放任务

| Codeberg PR | GitHub PR | 状态 |
|---|---|---|
| [#16](https://codeberg.org/WroughtMind/weibei/pulls/16) | [#485](https://github.com/WroughtMind/weibei/pull/485) | head 相同，复用原草稿与讨论 |
| [#44](https://codeberg.org/WroughtMind/weibei/pulls/44) | [#513](https://github.com/WroughtMind/weibei/pull/513) | 阅读位置与恢复，迁回草稿 |
| [#45](https://codeberg.org/WroughtMind/weibei/pulls/45) | [#514](https://github.com/WroughtMind/weibei/pull/514) | 浮窗图示、公式与字号，迁回草稿 |
| [#46](https://codeberg.org/WroughtMind/weibei/pulls/46) | [#515](https://github.com/WroughtMind/weibei/pull/515) | 栏位回弹、错误详情及安全，迁回草稿 |
| [#47](https://codeberg.org/WroughtMind/weibei/pulls/47) | [#516](https://github.com/WroughtMind/weibei/pull/516) | 日期与时区，迁回草稿 |
| [#48](https://codeberg.org/WroughtMind/weibei/pulls/48) | [#517](https://github.com/WroughtMind/weibei/pull/517) | 模型列表与选择，迁回草稿 |
| [#49](https://codeberg.org/WroughtMind/weibei/pulls/49) | [#518](https://github.com/WroughtMind/weibei/pull/518) | 文件导入确认，迁回草稿 |
| [#50](https://codeberg.org/WroughtMind/weibei/pulls/50) | [#519](https://github.com/WroughtMind/weibei/pull/519) | 连接卡片，迁回草稿 |

迁回任务不等于批准功能合并。原作者与正文在各 PR 中标识。[来源 PR/评论快照](codeberg-pr-archive-2026-09-30.json)保留 50 个 Codeberg PR 与 11 条评论；来源原文不表示迁移操作者的新判断。

## 官网、字体与更新链路

- Codeberg `pages` main `fae48c4a6e64ae386acc8208a574e72a34a16a82` 的 297 个网站文件与来源 main 的 `website/` 相同，仅另有 Codeberg `.domains`。独立历史保存为 [`codeberg/pages-history-20260930`](https://github.com/WroughtMind/weibei/tree/codeberg/pages-history-20260930)
- 官网使用现有 GitHub Pages 工作流与 `https://wroughtmind.github.io/weibei/`；原 Codeberg 自定义域名的 DNS 未更改
- 字体库继续使用 [`taekchef/weibei-english-font`](https://github.com/taekchef/weibei-english-font)；Codeberg 的无共同祖先历史保存为 `codeberg/history-20260930`。保留 GitHub 默认分支的 OFL 声明与较安全的构建脚本，不倒灌旧 Arial 缺字回退或硬编码本机路径。两个 TTF 的字形、度量和字符映射表一致，差异仅在 `head` 与 `name` 表
- App 反馈入口恢复为 GitHub Issues；安装包发布、下载链接和 Sparkle Feed 原本已指向 GitHub，不更换更新公钥
- 迁移检查时 GitHub Releases 为空，架构 appcast 返回 404。没有发现可据此声称已恢复的旧 DMG；新安装包须完成双架构构建、签名、验证和发布授权
- 早期测试公钥版本需要手动安装一次正式公钥版本，详见[双架构发布说明](../releases/dual-architecture.md)

## 验证边界

两端完整非浅层 Git 对象通过 `git fsck --full`；迁回的远端 refs 按 SHA 复核。已抓取历史未发现 Git LFS 指针；来源 main 和 8 个开放任务 head 未发现子模块。本机未提交、stash、未跟踪文件不在远端迁移范围。功能与安装包验收以对应当前 SHA 的 CI 和发布记录为准。
