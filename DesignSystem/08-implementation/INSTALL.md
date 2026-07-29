# 接入仓库

## 当前 SwiftPM 打包方式

仓库没有 Xcode project，也没有已接入的 Asset Catalog。Swift CLI 的打包
核心负责创建 `魏碑.app`、Info.plist 和签名，因此当前使用 `AppIcon.icns`。
根目录 Makefile 只是稳定的编排入口，不复制资产或实现打包逻辑。

1. 把整个 `DesignSystem/` 放在仓库根目录。
2. 在 Swift 打包核心中完成三件事：检查 ICNS、复制到 `Contents/Resources`、写入 `CFBundleIconFile`。
3. 在 `script/verify_release_metadata.sh` 增加图标文件与 plist 引用校验。
4. 运行：

```bash
make package
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' 'dist/魏碑.app/Contents/Info.plist'
ls -lh 'dist/魏碑.app/Contents/Resources/AppIcon.icns'
```

5. 若 Finder 缓存旧图标，改一次构建号并重新复制应用；不要以缓存现象判断 ICNS 无效。

## 将来迁移 Xcode Asset Catalog

使用 `assets/app-icon/AppIcon.appiconset/`。确保构建系统实际编译 asset catalog，并设置 App Icon 名称；不要同时保留一套无人维护的 ICNS 和一套不同图的 appiconset。

## 尚未自动完成的事

这里没有直接改 GitHub `main`，也没有在 macOS 14 实机运行 `iconutil`、签名和 Dock / Finder 验收。资产结构与 ICNS 头已校验；正式发布前仍需完成 `09-qa/release-checklist.md`。
