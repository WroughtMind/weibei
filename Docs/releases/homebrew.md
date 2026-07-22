# Homebrew 分发方案

魏碑通过自有 Tap 提供 Cask。Cask 下载 GitHub Release 中同一份 DMG，并用固定 SHA-256 校验后把 `魏碑.app` 安装到“应用程序”。

计划中的公开结构：

```text
taekchef/weibei                 GitHub Release 与源码
taekchef/homebrew-tap           Casks/weibei.rb
```

安装命令：

```bash
brew install --cask taekchef/tap/weibei
```

当前两个仓库仍不会自动公开。只有当 `v1.0.0` Release 的 DMG 地址和最终 SHA-256 已存在，Cask 才能由普通用户真实安装；在此之前仓库内只保留可由发布流程填充并验证的配方模板。

Homebrew 不会让未公证应用自动获得 Apple 信任。首次启动仍按 README 中的单应用放行步骤处理，不使用全局关闭 Gatekeeper 或已废弃的免隔离参数。
