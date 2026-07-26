# 接入仓库

## 当前 SwiftPM 手工打包方式

仓库没有 Xcode project，也没有已接入的 Asset Catalog。`script/build_and_run.sh` 自己创建 `魏碑.app`、Info.plist 和签名，并已使用 `AppIcon.icns`：

1. 资产真源位于仓库根目录的 `DesignSystem/`。
2. 打包脚本检查 ICNS、复制到 `Contents/Resources`，并写入 `CFBundleIconFile`。
3. `script/verify_release_metadata.sh` 校验图标文件、plist 引用和发布元数据。
4. 修改资产后运行：

```bash
DesignSystem/scripts/build-assets.sh
DesignSystem/scripts/verify-assets.sh
./script/build_and_run.sh package
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' 'dist/魏碑.app/Contents/Info.plist'
ls -lh 'dist/魏碑.app/Contents/Resources/AppIcon.icns'
```

5. 若 Finder 缓存旧图标，改一次构建号并重新复制应用；不要以缓存现象判断 ICNS 无效。

## 将来迁移 Xcode Asset Catalog

使用 `assets/app-icon/AppIcon.appiconset/`。确保构建系统实际编译 asset catalog，并设置 App Icon 名称；不要同时保留一套无人维护的 ICNS 和一套不同图的 appiconset。

## 发布前仍需人工完成的事

自动检查覆盖资产结构、ICNS 头、manifest 漂移、应用包引用和签名。正式发布前仍需按 `09-qa/release-checklist.md` 在支持的 macOS 实机完成 Dock / Finder 外观验收，避免把系统图标缓存误判成资产失效。
