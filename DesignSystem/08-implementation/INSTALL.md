# 接入仓库

## 当前 SwiftPM 手工打包方式

仓库没有 Xcode project，也没有已接入的 Asset Catalog。`script/build_and_run.sh` 自己创建 `魏碑.app`、Info.plist 和签名，因此最稳妥的第一步是使用 `AppIcon.icns`。

1. 把整个 `DesignSystem/` 放在仓库根目录。
2. `script/build_and_run.sh` 已负责检查 ICNS、复制到 `Contents/Resources` 并写入 `CFBundleIconFile`。
3. 在 `swift run WeiBeiDev verify-release-metadata`（原 `script/verify_release_metadata.sh`，已迁移为 Swift 工具子命令）增加图标文件与 plist 引用校验。
4. 运行：

```bash
./script/build_and_run.sh package
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' 'dist/魏碑.app/Contents/Info.plist'
ls -lh 'dist/魏碑.app/Contents/Resources/AppIcon.icns'
```

5. 若 Finder 缓存旧图标，改一次构建号并重新复制应用；不要以缓存现象判断 ICNS 无效。

## 将来迁移 Xcode Asset Catalog

使用 `assets/app-icon/AppIcon.appiconset/`。确保构建系统实际编译 asset catalog，并设置 App Icon 名称；不要同时保留一套无人维护的 ICNS 和一套不同图的 appiconset。

## 尚未自动完成的事

正式发布前仍需按 `09-qa/release-checklist.md` 完成签名和 Dock / Finder 验收。
