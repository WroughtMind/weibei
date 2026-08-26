# 接入仓库

## 当前 SwiftPM 手工打包方式

仓库没有 Xcode project，`script/build_and_run.sh` 自己创建 `魏碑.app`、Info.plist 和签名。脚本使用 Xcode 自带的资源编译器处理 `AppIcon.icon`，不需要为图标引入 Xcode project。

1. 把整个 `DesignSystem/` 放在仓库根目录。
2. `script/build_and_run.sh` 编译并复制 `Assets.car` 与 `AppIcon.icns`，同时写入 `CFBundleIconName` 和 `CFBundleIconFile`。
3. `swift run WeiBeiDev verify-release-metadata` 检查动态资源、传统图标和 plist 引用。
4. 运行：

```bash
./script/build_and_run.sh package
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' 'dist/魏碑.app/Contents/Info.plist'
ls -lh 'dist/魏碑.app/Contents/Resources/Assets.car'
ls -lh 'dist/魏碑.app/Contents/Resources/AppIcon.icns'
```

5. 若 Finder 缓存旧图标，改一次构建号并重新复制应用；不要以缓存现象判断 ICNS 无效。

## 尚未自动完成的事

正式发布前仍需按 `09-qa/release-checklist.md` 完成签名和 Dock / Finder 验收。
