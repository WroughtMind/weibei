# Homebrew 分发方案

魏碑通过自有 Tap 提供 Cask。Cask 按当前 Mac 架构下载 GitHub Release 中对应的原生 DMG，并用各自固定的 SHA-256 校验后把 `魏碑.app` 安装到“应用程序”。

计划中的公开结构：

```text
WroughtMind/weibei              GitHub Release 与源码
taekchef/homebrew-tap           Casks/weibei.rb
```

安装命令：

```bash
brew install --cask taekchef/tap/weibei
```

双架构发布工作流会在两套 DMG 都通过后生成 `weibei.rb`，其中使用 Homebrew 的 `arch arm:/intel:` 与双 `sha256` 语法。该配方随 GitHub Release 一起提供；同步到 Tap 仍是独立、可审计的发布动作，不由 PR 检查自动写入外部仓库。

Homebrew 不会让未公证应用自动获得 Apple 信任。首次启动仍按 README 中的单应用放行步骤处理，不使用全局关闭 Gatekeeper 或已废弃的免隔离参数。
