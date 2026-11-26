# 接入仓库

## 应用工程与打包

发布使用 [Mac Catalyst 工程](../../App/WeiBei.xcodeproj)。图标和资源由工程编译，打包入口生成对应架构的应用。SwiftPM 提供共用代码和检查工具。

```bash
npm ci
./script/build_and_run.sh package
swift run WeiBeiDev verify-release-metadata 'dist/魏碑.app'
```

修改应用图标后，在候选包中检查 Finder 和 Dock 的实际显示。双架构打包见[发布流程](../../Docs/releases/dual-architecture.md)。

## 尚未自动完成的事

正式发布前仍需按 `09-qa/release-checklist.md` 完成签名和 Dock / Finder 验收。
